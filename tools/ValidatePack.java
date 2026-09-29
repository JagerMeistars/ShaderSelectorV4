import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import com.google.gson.*;
import com.mojang.serialization.JsonOps;
import com.mojang.renderpearl.api.pipeline.ShaderSource.CachedIncludeSource;
import com.mojang.renderpearl.api.pipeline.ShaderType;
import com.mojang.renderpearl.frontend.shaders.SPIRVModule;
import net.minecraft.resources.Identifier;
import net.minecraft.client.renderer.PostChainConfig;
import net.minecraft.server.packs.metadata.pack.PackFormat;
import net.minecraft.server.packs.PackType;
import org.lwjgl.util.shaderc.*;
import static org.lwjgl.util.shaderc.Shaderc.*;
import static org.lwjgl.system.MemoryUtil.*;

public class ValidatePack {
    static ZipFile pack, vanilla;
    static Map<String, CachedIncludeSource> includes = new HashMap<>();
    static Map<String, Set<String>> samplers = new HashMap<>();
    static int failures = 0;
    static String read(String path) throws Exception {
        ZipFile z = pack.getEntry(path) != null ? pack : vanilla;
        var entry = z.getEntry(path);
        if (entry == null) throw new IllegalArgumentException("Missing resource: " + path);
        return new String(z.getInputStream(entry).readAllBytes(), StandardCharsets.UTF_8);
    }
    static String shaderPath(String id, String ext) {
        var i = Identifier.parse(id);
        return "assets/" + i.getNamespace() + "/shaders/" + i.getPath() + ext;
    }
    static void fail(String text) { failures++; System.out.println("FAIL " + text); }
    public static void main(String[] args) throws Exception {
        pack = new ZipFile(args[0]); vanilla = new ZipFile(args[1]);
        long compiler = shaderc_compiler_initialize();
        long options = shaderc_compile_options_initialize();
        // These settings match 26.3 GlslCompiler.createBaseShaderOptions().
        // Both Minecraft render backends compile GLSL to Vulkan 1.2 SPIR-V first.
        shaderc_compile_options_set_target_env(options, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_2);
        shaderc_compile_options_set_auto_bind_uniforms(options, true);
        shaderc_compile_options_set_preserve_bindings(options, false);
        shaderc_compile_options_set_generate_debug_info(options);
        shaderc_compile_options_set_optimization_level(options, shaderc_optimization_level_zero);
        ShadercIncludeResolve resolver = ShadercIncludeResolve.create((u, name, type, source, depth) -> {
            String id = memUTF8(name);
            return includes.computeIfAbsent(id, key -> {
                try {
                    Identifier i = Identifier.parse(key);
                    return CachedIncludeSource.create(i, read("assets/" + i.getNamespace() + "/shaders/include/" + i.getPath()));
                } catch (Exception e) { return CachedIncludeSource.createError(e.toString()); }
            }).includeResultPtr();
        });
        ShadercIncludeResultRelease release = ShadercIncludeResultRelease.create((u, result) -> {});
        shaderc_compile_options_set_include_callbacks(options, resolver, release, 0);
        Set<String> shaderPaths = new TreeSet<>();
        List<Map.Entry<String, JsonObject>> configs = new ArrayList<>();
        var entries = pack.entries();
        while (entries.hasMoreElements()) {
            String path = entries.nextElement().getName();
            if (path.endsWith(".fsh") || path.endsWith(".vsh")) shaderPaths.add(path);
            if (path.contains("/post_effect/") && path.endsWith(".json")) {
                JsonObject json = JsonParser.parseString(read(path)).getAsJsonObject();
                configs.add(Map.entry(path, json));
                var decoded = PostChainConfig.CODEC.parse(JsonOps.INSTANCE, json);
                if (decoded.error().isPresent()) fail(path + ": " + decoded.error().get());
                for (var elem : json.getAsJsonArray("passes")) {
                    var pass = elem.getAsJsonObject();
                    shaderPaths.add(shaderPath(pass.get("vertex_shader").getAsString(), ".vsh"));
                    shaderPaths.add(shaderPath(pass.get("fragment_shader").getAsString(), ".fsh"));
                }
            }
        }
        System.out.println("POST_CHAIN_JSONS " + configs.size());
        var metadata = PackFormat.packCodec(PackType.CLIENT_RESOURCES).codec().parse(JsonOps.INSTANCE, JsonParser.parseString(read("pack.mcmeta")).getAsJsonObject().get("pack"));
        if (metadata.error().isPresent()) fail("pack.mcmeta: " + metadata.error().get());
        else System.out.println("PACK_FORMAT " + metadata.result().get());
        int compiled = 0;
        for (String path : shaderPaths) {
            boolean vertex = path.endsWith(".vsh");
            long result = shaderc_compile_into_spv(compiler, read(path), vertex ? shaderc_vertex_shader : shaderc_fragment_shader, path, "main", options);
            if (shaderc_result_get_compilation_status(result) != shaderc_compilation_status_success) {
                fail(path + "\n" + shaderc_result_get_error_message(result));
            } else {
                compiled++;
                ByteBuffer bytes = shaderc_result_get_bytes(result);
                ByteBuffer copy = memAlloc(bytes.remaining()); copy.put(bytes).flip();
                try (SPIRVModule module = new SPIRVModule(copy, vertex ? ShaderType.VERTEX : ShaderType.FRAGMENT)) {
                    var reflect = module.reflect();
                    Set<String> required = new TreeSet<>();
                    for (var descriptor : reflect.descriptors())
                        if (descriptor.name().endsWith("Sampler")) required.add(descriptor.name());
                    samplers.put(path, required);
                    System.out.println("COMPILED " + path + " SAMPLERS " + required);
                }
            }
            shaderc_result_release(result);
        }
        for (var entry : configs) {
            Set<String> targets = new HashSet<>(entry.getValue().getAsJsonObject("targets").keySet());
            targets.add("minecraft:main");
            for (var elem : entry.getValue().getAsJsonArray("passes")) {
                var pass = elem.getAsJsonObject();
                String shader = shaderPath(pass.get("fragment_shader").getAsString(), ".fsh");
                Set<String> bound = new TreeSet<>();
                for (var inp : pass.getAsJsonArray("inputs")) {
                    var input = inp.getAsJsonObject();
                    bound.add(input.get("sampler_name").getAsString() + "Sampler");
                    if (input.has("target") && !targets.contains(input.get("target").getAsString())) fail(entry.getKey() + " missing input target " + input.get("target"));
                    if (input.has("location")) {
                        // PostChain.createPass prepends textures/effect/ itself.
                        var location = Identifier.parse(input.get("location").getAsString());
                        String texturePath = "assets/" + location.getNamespace() + "/textures/effect/" + location.getPath() + ".png";
                        ZipFile source = pack.getEntry(texturePath) != null ? pack : vanilla;
                        var textureEntry = source.getEntry(texturePath);
                        if (textureEntry == null) fail(entry.getKey() + " missing external texture " + texturePath);
                        else {
                            try (var stream = source.getInputStream(textureEntry)) {
                                var image = javax.imageio.ImageIO.read(stream);
                                if (image == null) fail(entry.getKey() + " unreadable texture " + texturePath);
                                else if (image.getWidth() != input.get("width").getAsInt() || image.getHeight() != input.get("height").getAsInt())
                                    fail(entry.getKey() + " external texture dimensions disagree with " + texturePath);
                            }
                        }
                    }
                }
                if (!targets.contains(pass.get("output").getAsString())) fail(entry.getKey() + " missing output target");
                if (samplers.containsKey(shader) && !bound.containsAll(samplers.get(shader))) {
                    Set<String> missing = new TreeSet<>(samplers.get(shader)); missing.removeAll(bound);
                    fail(entry.getKey() + " unbound samplers " + missing);
                }
            }
        }
        for (String phase : List.of("OIT_DEPTH_BOUNDS", "OIT_TRANSMITTANCE", "OIT_ACCUMULATE")) {
            String path = "assets/minecraft/shaders/core/particle.fsh";
            String defines = "#define OIT\n#define OIT_WAVELET_RANK 2\n#define OIT_COEFF_COUNT 8\n#define OIT_COEFF_ATTACHMENT_COUNT 2\n#define " + phase + "\n";
            if (!phase.equals("OIT_ACCUMULATE")) defines += "#define OIT_ALPHA_ONLY\n";
            String source = read(path).replace("#version 330", "#version 330\n" + defines);
            long result = shaderc_compile_into_spv(compiler, source, shaderc_fragment_shader, path, "main", options);
            if (shaderc_result_get_compilation_status(result) != shaderc_compilation_status_success)
                fail(phase + "\n" + shaderc_result_get_error_message(result));
            else System.out.println("COMPILED particle " + phase);
            shaderc_result_release(result);
        }
        includes.values().forEach(CachedIncludeSource::close);
        resolver.close(); release.close();
        shaderc_compile_options_release(options); shaderc_compiler_release(compiler);
        pack.close(); vanilla.close();
        System.out.println("SUMMARY shaders=" + shaderPaths.size() + " compiled=" + compiled + " effects=" + configs.size() + " failures=" + failures);
        System.exit(failures == 0 ? 0 : 1);
    }
}
