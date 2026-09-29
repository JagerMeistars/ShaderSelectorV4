from pathlib import Path
import json
import subprocess
import sys

# Usage: python tools/validate.py PACK.zip LOG.txt PRISMLAUNCHER_DIR
BASE = Path(sys.argv[3])
WORK = Path(__file__).parent
CLIENT = BASE / 'libraries/com/mojang/minecraft/26.3/minecraft-26.3-client.jar'
classpath = [str(WORK), str(CLIENT)]
for metadata in ['meta/net.minecraft/26.3.json', 'meta/org.lwjgl3/3.4.3.json']:
    for lib in json.loads((BASE / metadata).read_text())['libraries']:
        group, artifact, version, *classifier = lib['name'].split(':')
        if 'natives-' in artifact and not artifact.endswith('natives-windows'):
            continue
        suffix = '-' + classifier[0] if classifier else ''
        path = BASE / 'libraries' / group.replace('.', '/') / artifact / version / f'{artifact}-{version}{suffix}.jar'
        if path.exists():
            classpath.append(str(path))
cp = ';'.join(classpath)
java = BASE / 'java/java-runtime-epsilon/bin'
subprocess.run([str(java / 'javac.exe'), '-cp', cp, str(WORK / 'ValidatePack.java')], check=True, cwd=WORK)
result = subprocess.run([str(java / 'java.exe'), '--enable-native-access=ALL-UNNAMED', '-cp', cp, 'ValidatePack', str(Path(sys.argv[1]).resolve()), str(CLIENT)], cwd=WORK, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
log = WORK / sys.argv[2]
log.write_bytes(result.stdout)
print(result.stdout.decode('utf-8', errors='replace'))
sys.exit(result.returncode)
