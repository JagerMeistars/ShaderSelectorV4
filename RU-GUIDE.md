# ShaderSelector V4 — Полное руководство

## Что это такое

ShaderSelector — это ресурспак-фреймворк для Minecraft, который создает мост между датапаками и пост-процессинг шейдерами. Он позволяет управлять визуальными эффектами с помощью команд, используя цветные частицы как канал передачи данных.

---

## Структура проекта

```
shaderselector/
├── pack.mcmeta                                   # Метаданные пака
└── assets/
    ├── minecraft/                                 # Переопределения ванильных файлов
    │   ├── post_effect/
    │   │   └── transparency.json                  # Пайплайн пост-обработки (порядок проходов)
    │   └── shaders/core/
    │       ├── particle.vsh                       # Вершинный шейдер частиц (модифицирован)
    │       └── particle.fsh                       # Фрагментный шейдер частиц (модифицирован)
    └── shader_selector/                           # Пространство имен фреймворка
        └── shaders/
            ├── include/
            │   ├── marker_settings.glsl           # Определения маркеров (каналы, операции)
            │   ├── utils.glsl                     # Кодирование/декодирование float <-> RGBA
            │   └── data_reader.glsl               # Утилита чтения значений каналов
            └── post/
                ├── data.fsh                       # Ядро: обработка маркеров и интерполяция
                ├── shader.fsh                     # ПРИМЕР: эффекты поворота и ч/б
                └── internal/
                    ├── blit.fsh                   # Простое копирование текстуры
                    └── remove_particles.fsh       # Удаление маркеров из рендера частиц
```

---

## Как это работает — общая схема

### Принцип

Minecraft не предоставляет прямого способа передать данные из команд в шейдеры. ShaderSelector обходит это ограничение, используя **частицы-маркеры**: команда спавнит частицу `entity_effect` со специальным цветом (R=254, G=идентификатор, B=значение, A=251), а шейдер читает цвет этой частицы и извлекает из него данные.

### Почему именно `entity_effect`?

Маркер идентифицируется по 4 каналам цвета: R, G, B и **A (alpha)**. Все маркеры используют `alpha=251`. Частицы типа `dust` не позволяют задать alpha — она всегда начинается с 1.0 (255). Частица `entity_effect` — единственный стандартный тип, где можно контролировать все 4 компонента RGBA.

### Поток данных

```
Команда в датапаке
    │
    ▼
Спавн частицы entity_effect с цветом-маркером (R=254, G=id, B=значение, A=251)
    │
    ▼
particle.vsh: обнаруживает маркер по цвету (R==254, G+A совпадают),
              перемещает частицу в фиксированную позицию на экране
    │
    ▼
particle.fsh: записывает цвет маркера (RGB + A=255) в буфер частиц
    │
    ▼
data.fsh: читает маркер из буфера частиц, обновляет persistent data-текстуру (5x3 пикселей)
    │
    ▼
remove_particles.fsh: убирает маркер из отображения (игрок не видит артефактов)
    │
    ▼
shader.fsh (ваш эффект): читает значения из data-текстуры через readChannel() и применяет эффект
```

### Двойная проверка маркера

Маркер проверяется в двух местах по-разному:

| Этап | Файл | Что проверяется | Зачем |
|------|-------|-----------------|-------|
| Vertex shader | `particle.vsh` | `iColor.r == 254` и `iColor.ga == ivec2(green, alpha)` | Распознать маркер среди всех частиц, переместить на нужный пиксель |
| Data shader | `data.fsh` | `particleColor.rga == ivec3(254, green, 255)` | Прочитать значение из буфера (alpha=255, потому что particle.fsh принудительно ставит A=255) |

---

## Ключевые файлы — подробное описание

### 1. `marker_settings.glsl` — Определение маркеров

Это главный конфигурационный файл. Здесь вы определяете **каналы** (каждый канал = один управляемый параметр) и **маркеры** (конкретные способы воздействия на канал).

```glsl
// Определите каналы — каждый канал хранит одно float-значение (0.0 – 1.0)
#define EXAMPLE_GREYSCALE_CHANNEL 1
#define EXAMPLE_ROTATION_CHANNEL 2

// Определите маркеры
// Формат: ADD_MARKER(channel, green, alpha, op, rate)
#define LIST_MARKERS \
    ADD_MARKER(EXAMPLE_GREYSCALE_CHANNEL, 253, 251, 1, 0.1) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 251, 251, 0, 0.0) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 252, 251, 4, 0.4)
```

**Параметры ADD_MARKER:**

| Параметр | Описание |
|----------|----------|
| `channel` | Номер канала (строка в data-текстуре), начиная с 1 |
| `green` | Значение зеленого канала маркера (0–255). Уникальный идентификатор в паре с `alpha` |
| `alpha` | Значение альфа-канала маркера (0–255). Второй идентификатор |
| `op` | Тип операции/интерполяции (см. раздел ниже) |
| `rate` | Скорость (для op 1,2) или ускорение (для op 3,4) интерполяции |

> **Важно:** Один канал может иметь несколько маркеров с разными операциями. Например, `EXAMPLE_ROTATION_CHANNEL` имеет два маркера: один для мгновенной установки (op=0), другой для циклического вращения с ускорением (op=4).

**`MARKER_RED` (254)** — красный канал, по которому шейдер распознает, что частица является маркером, а не обычной частицей.

### 2. Операции интерполяции (op)

Когда вы передаете значение через маркер, оно не обязательно применяется мгновенно. Система поддерживает плавную интерполяцию:

| Op | Название | Поведение | Параметр rate |
|----|----------|-----------|---------------|
| **0** | Set | Мгновенная установка значения. Без анимации | Не используется (0.0) |
| **1** | Constant velocity | Линейное движение к целевому значению с постоянной скоростью | Скорость (units/tick) |
| **2** | Cyclic constant velocity | Как op=1, но значение зацикливается в диапазоне 0.0–1.0 (кратчайший путь) | Скорость |
| **3** | Accelerated motion | Движение с ускорением (плавный разгон и торможение) | Ускорение |
| **4** | Cyclic accelerated | Как op=3, но с зацикливанием 0.0–1.0 | Ускорение |

### 3. Data-текстура (5x3 пикселей)

Вся информация хранится в персистентной текстуре размером 5x3 пикселя. Каждый пиксель кодирует float через 4 байта RGBA.

```
Столбец:     0              1              2              3              4
          ┌──────────┬──────────────┬──────────────┬──────────────┬──────────────┐
Строка 0: │ GameTime │              │              │              │              │  (время)
          ├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
Строка 1: │ Маркер   │ Время смены  │ Ускорение    │ Скорость     │ Значение     │  (канал 1)
          ├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
Строка 2: │ Маркер   │ Время смены  │ Ускорение    │ Скорость     │ Значение     │  (канал 2)
          └──────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

- **Столбец 0:** Последний увиденный маркер (R=254, G=операция, B=целевое значение)
- **Столбец 1:** Время последнего изменения маркера
- **Столбец 2:** Текущее ускорение
- **Столбец 3:** Текущая скорость
- **Столбец 4:** Текущее интерполированное значение (то, что вы читаете в своем шейдере)

### 4. `utils.glsl` — Кодирование float

Шейдеры хранят float-значения в RGBA-пикселях (4 байта = 32 бита):

```glsl
// Кодирует float в 4 байта RGBA
vec4 encodeFloat(float value);

// Декодирует RGBA обратно в float
float decodeColor(vec4 color);
```

### 5. `data_reader.glsl` — Чтение каналов

Простейшая утилита для чтения текущего значения канала в вашем шейдере:

```glsl
// Возвращает текущее интерполированное значение канала
float readChannel(int channel);
```

Использование:
```glsl
float greyscale = readChannel(EXAMPLE_GREYSCALE_CHANNEL); // 0.0 – 1.0
float rotation = readChannel(EXAMPLE_ROTATION_CHANNEL);   // 0.0 – 1.0
```

---

## Формат команды для отправки маркера

### Цвет маркера

Каждый маркер — это частица с цветом из 4 компонентов:

| Канал цвета | Значение | Описание |
|-------------|----------|----------|
| **R (red)** | Всегда **254** | Сигнатура — "я маркер" |
| **G (green)** | Из `ADD_MARKER` | Идентификатор маркера |
| **B (blue)** | 0–255 | Передаваемое значение |
| **A (alpha)** | Из `ADD_MARKER` (251) | Второй идентификатор |

### Команда particle

Частица `entity_effect` принимает цвет как упакованное целое число в формате ARGB:

```
particle entity_effect{color:<ARGB_INT>} <x> <y> <z>
```

**Формула ARGB:**
```
ARGB = (A << 24) | (R << 16) | (G << 8) | B
```

Для наших маркеров (A=251, R=254):
```
ARGB = (251 << 24) | (254 << 16) | (green << 8) | value
     = -67175168 + (green - 253) * 256 + value     // для green ≈ 253
```

### Предвычисленные базовые значения

Для удобства — базовые ARGB (без value, т.е. B=0):

| Маркер | green | Базовый ARGB | Формула с value |
|--------|-------|-------------|-----------------|
| Greyscale | 253 | **-67175168** | `-67175168 + value` |
| Rotation (set) | 251 | **-67175680** | `-67175680 + value` |
| Rotation (cyclic) | 252 | **-67175424** | `-67175424 + value` |

> **Как получить:** `-67175168 + value` — просто прибавьте нужное значение (0–255) к базовому числу.

### Конвертация значений

Синий канал (B) — это целое число 0–255. Шейдер нормализует его:

| Операция | Формула в шейдере | B=0 | B=128 | B=255 |
|----------|-------------------|-----|-------|-------|
| Op 0, 1, 3 (обычные) | `B / 255.0` | 0.0 | 0.502 | 1.0 |
| Op 2, 4 (циклические) | `B / 256.0` | 0.0 | 0.5 | 0.996 |

Для поворота в градусах: `градусы = (B / 256.0) * 360.0`

| Градусы | Значение B | Формула |
|---------|-----------|---------|
| 0° | 0 | `0 / 256 * 360` |
| 45° | 32 | `32 / 256 * 360` |
| 90° | 64 | `64 / 256 * 360` |
| 180° | 128 | `128 / 256 * 360` |
| 270° | 192 | `192 / 256 * 360` |

---

## Примеры использования

Все примеры ниже можно вводить в чат, вставлять в командные блоки или использовать в функциях датапака (`.mcfunction`).

> **Важно:** Частица должна быть видна на экране игрока хотя бы 1 кадр. Спавните ее рядом с камерой. Шейдер обнаружит маркер и уберет его из рендера — игрок ничего не увидит.

---

### Пример 1: Черно-белый фильтр (Greyscale)

Маркер: `green=253`, `alpha=251`, `op=1` (constant velocity, rate=0.1).
Значение канала плавно движется к целевому со скоростью 0.1/тик.

**Включить (плавно перейти в полный ч/б):**
```mcfunction
# B=255 -> target = 1.0 (100% greyscale)
# ARGB = -67175168 + 255 = -67174913
particle entity_effect{color:-67174913} ~ ~1 ~
```

**Выключить (плавно вернуть цвет):**
```mcfunction
# B=0 -> target = 0.0 (0% greyscale, полный цвет)
# ARGB = -67175168 + 0 = -67175168
particle entity_effect{color:-67175168} ~ ~1 ~
```

**Установить на 50%:**
```mcfunction
# B=128 -> target ≈ 0.502
# ARGB = -67175168 + 128 = -67175040
particle entity_effect{color:-67175040} ~ ~1 ~
```

**Установить на 25%:**
```mcfunction
# B=64 -> target ≈ 0.251
# ARGB = -67175168 + 64 = -67175104
particle entity_effect{color:-67175104} ~ ~1 ~
```

> **Поведение:** Поскольку op=1 (constant velocity) с rate=0.1, значение не скачет мгновенно, а плавно ползет к цели. Скорость перехода фиксирована — неважно, насколько далеко текущее значение от целевого.

---

### Пример 2: Поворот экрана — мгновенная установка

Маркер: `green=251`, `alpha=251`, `op=0` (set).
Значение устанавливается **мгновенно**, без анимации.

**Повернуть на 90°:**
```mcfunction
# B=64 -> 64/255 ≈ 0.251 -> 0.251 * 360 ≈ 90°
# ARGB = -67175680 + 64 = -67175616
particle entity_effect{color:-67175616} ~ ~1 ~
```

**Повернуть на 180°:**
```mcfunction
# B=128 -> 128/255 ≈ 0.502 -> ≈ 181°
# ARGB = -67175680 + 128 = -67175552
particle entity_effect{color:-67175552} ~ ~1 ~
```

**Повернуть на 45°:**
```mcfunction
# B=32 -> 32/255 ≈ 0.125 -> ≈ 45°
# ARGB = -67175680 + 32 = -67175648
particle entity_effect{color:-67175648} ~ ~1 ~
```

**Сбросить поворот (0°):**
```mcfunction
# B=0 -> 0°
# ARGB = -67175680
particle entity_effect{color:-67175680} ~ ~1 ~
```

> **Поведение:** Экран мгновенно поворачивается на заданный угол. Без плавности — щелчок и готово.

---

### Пример 3: Поворот экрана — плавное циклическое вращение

Маркер: `green=252`, `alpha=251`, `op=4` (cyclic accelerated, rate=0.4).
Значение плавно движется к цели с ускорением, зацикливаясь через 0.0–1.0.

**Запустить вращение к 180°:**
```mcfunction
# B=128 -> 128/256 = 0.5 -> 0.5 * 360 = 180°
# ARGB = -67175424 + 128 = -67175296
particle entity_effect{color:-67175296} ~ ~1 ~
```

**Запустить вращение к 270°:**
```mcfunction
# B=192 -> 192/256 = 0.75 -> 270°
# ARGB = -67175424 + 192 = -67175232
particle entity_effect{color:-67175232} ~ ~1 ~
```

**Остановить вращение (вернуть к 0°):**
```mcfunction
# B=0 -> target = 0°
# ARGB = -67175424
particle entity_effect{color:-67175424} ~ ~1 ~
```

> **Поведение:** Экран плавно разгоняется и тормозит, приходя к заданному углу. Циклическое — значит при переходе от 350° к 10° он пойдет кратчайшим путем (через 360°/0°), а не обратно через 180°.

---

### Пример 4: Комбинирование эффектов

Эффекты на разных каналах работают **одновременно и независимо**. Можно комбинировать:

**Включить ч/б + повернуть на 45°:**
```mcfunction
# Greyscale на максимум
particle entity_effect{color:-67174913} ~ ~1 ~
# Поворот на 45° мгновенно
particle entity_effect{color:-67175648} ~ ~1 ~
```

**Плавный ч/б + плавное вращение к 180°:**
```mcfunction
# Greyscale плавно к 100%
particle entity_effect{color:-67174913} ~ ~1 ~
# Вращение плавно к 180°
particle entity_effect{color:-67175296} ~ ~1 ~
```

**Выключить всё:**
```mcfunction
# Greyscale к 0
particle entity_effect{color:-67175168} ~ ~1 ~
# Поворот мгновенно к 0°
particle entity_effect{color:-67175680} ~ ~1 ~
```

---

### Пример 5: Использование в датапаке

#### Структура датапака

```
my_effects_datapack/
├── pack.mcmeta
└── data/
    └── my_effects/
        └── function/
            ├── greyscale_on.mcfunction
            ├── greyscale_off.mcfunction
            ├── spin_start.mcfunction
            ├── spin_stop.mcfunction
            └── reset_all.mcfunction
```

#### `pack.mcmeta`
```json
{
    "pack": {
        "pack_format": 75,
        "description": "Shader effects controller"
    }
}
```

#### `greyscale_on.mcfunction` — Плавно включить ч/б
```mcfunction
# Включить черно-белый фильтр (плавный переход)
# Спавним маркер на позиции игрока (чуть выше, чтобы точно попасть на экран)
execute as @a at @s run particle entity_effect{color:-67174913} ^ ^ ^2
```

#### `greyscale_off.mcfunction` — Плавно выключить ч/б
```mcfunction
# Выключить черно-белый фильтр (плавный переход обратно)
execute as @a at @s run particle entity_effect{color:-67175168} ^ ^ ^2
```

#### `spin_start.mcfunction` — Запустить вращение
```mcfunction
# Начать плавное вращение экрана к 180°
execute as @a at @s run particle entity_effect{color:-67175296} ^ ^ ^2
```

#### `spin_stop.mcfunction` — Остановить вращение
```mcfunction
# Остановить вращение (плавно вернуть к 0°)
# Сначала циклический маркер к 0
execute as @a at @s run particle entity_effect{color:-67175424} ^ ^ ^2
```

#### `reset_all.mcfunction` — Сбросить все эффекты
```mcfunction
# Greyscale -> 0 (плавно)
execute as @a at @s run particle entity_effect{color:-67175168} ^ ^ ^2
# Rotation -> 0° (мгновенно)
execute as @a at @s run particle entity_effect{color:-67175680} ^ ^ ^2
```

#### Использование из чата
```
/function my_effects:greyscale_on
/function my_effects:greyscale_off
/function my_effects:spin_start
/function my_effects:spin_stop
/function my_effects:reset_all
```

---

### Пример 6: Повторяющаяся отправка маркера (для удержания эффекта)

Маркер нужно отправить **один раз** — значение сохраняется в персистентной текстуре между кадрами. Однако если вы хотите **непрерывно менять значение** (например, анимировать по таймеру), можно отправлять маркеры каждый тик:

```mcfunction
# tick.mcfunction — вызывается каждый тик
# Плавно качаем greyscale на основе времени дня
execute store result score #time temp run time query daytime
execute if score #time temp matches 0..6000 as @a at @s run particle entity_effect{color:-67174913} ^ ^ ^2
execute if score #time temp matches 6001..12000 as @a at @s run particle entity_effect{color:-67175168} ^ ^ ^2
```

> **Примечание:** Отправка одного и того же маркера с тем же значением повторно — безвредна. Система проверяет, изменилось ли значение B, и если нет — не обновляет таймстемп.

---

### Пример 7: Вычисление ARGB для произвольного маркера

Если вы добавили свой маркер и хотите вычислить ARGB:

```
ARGB (signed 32-bit) = ((251 - 256) * 16777216) + (254 * 65536) + (green * 256) + value
                      = -83886080 + 16646144 + green * 256 + value
                      = -67239936 + green * 256 + value
```

**Упрощенная формула:**
```
ARGB = -67239936 + green * 256 + value
```

**Примеры:**
| green | value | ARGB |
|-------|-------|------|
| 253 | 0 | -67239936 + 64768 + 0 = **-67175168** |
| 253 | 255 | -67239936 + 64768 + 255 = **-67174913** |
| 251 | 0 | -67239936 + 64256 + 0 = **-67175680** |
| 252 | 128 | -67239936 + 64512 + 128 = **-67175296** |
| 250 | 100 | -67239936 + 64000 + 100 = **-67175836** |

---

## Справочная таблица: все маркеры из примера

| Эффект | Действие | green | op | Команда (B=значение) |
|--------|----------|-------|----|----------------------|
| Greyscale | Плавно к значению | 253 | 1 | `entity_effect{color:}` где ARGB = `-67175168 + B` |
| Rotation | Мгновенная установка | 251 | 0 | `entity_effect{color:}` где ARGB = `-67175680 + B` |
| Rotation | Плавное с ускорением | 252 | 4 | `entity_effect{color:}` где ARGB = `-67175424 + B` |

**Часто используемые готовые значения:**

| Действие | ARGB | Команда |
|----------|------|---------|
| Greyscale ON (100%) | -67174913 | `particle entity_effect{color:-67174913} ^ ^ ^2` |
| Greyscale OFF (0%) | -67175168 | `particle entity_effect{color:-67175168} ^ ^ ^2` |
| Greyscale 50% | -67175040 | `particle entity_effect{color:-67175040} ^ ^ ^2` |
| Rotation SET 0° | -67175680 | `particle entity_effect{color:-67175680} ^ ^ ^2` |
| Rotation SET 90° | -67175616 | `particle entity_effect{color:-67175616} ^ ^ ^2` |
| Rotation SET 180° | -67175552 | `particle entity_effect{color:-67175552} ^ ^ ^2` |
| Rotation SMOOTH 0° | -67175424 | `particle entity_effect{color:-67175424} ^ ^ ^2` |
| Rotation SMOOTH 90° | -67175360 | `particle entity_effect{color:-67175360} ^ ^ ^2` |
| Rotation SMOOTH 180° | -67175296 | `particle entity_effect{color:-67175296} ^ ^ ^2` |

---

## Как написать свой шейдер-эффект

### Шаг 1: Определите каналы

В `marker_settings.glsl` добавьте новые каналы и маркеры:

```glsl
// Новый канал
#define MY_BLUR_CHANNEL 3

// Добавьте маркер в LIST_MARKERS
#define LIST_MARKERS \
    ADD_MARKER(EXAMPLE_GREYSCALE_CHANNEL, 253, 251, 1, 0.1) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 251, 251, 0, 0.0) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 252, 251, 4, 0.4) \
    ADD_MARKER(MY_BLUR_CHANNEL, 250, 251, 1, 0.2)
```

> **Важно:** При добавлении нового канала с номером 3 нужно увеличить data-текстуру. В `transparency.json` измените высоту `data` и `data_swap` с 3 на 4:
> ```json
> "data": {"width": 5, "height": 4, "persistent": true},
> "data_swap": {"width": 5, "height": 4}
> ```

### Шаг 2: Создайте шейдер

Создайте файл в `assets/shader_selector/shaders/post/`, например `my_effect.fsh`:

```glsl
#version 330

uniform sampler2D MainSampler;   // Основное изображение
uniform sampler2D DataSampler;   // Data-текстура с значениями каналов

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

#moj_import <shader_selector:marker_settings.glsl>
#moj_import <shader_selector:utils.glsl>
#moj_import <shader_selector:data_reader.glsl>

in vec2 texCoord;
out vec4 fragColor;

void main() {
    // Читаем значение канала (от 0.0 до 1.0)
    float blurAmount = readChannel(MY_BLUR_CHANNEL);

    // Применяем эффект
    vec4 color = texture(MainSampler, texCoord);

    // Пример: простое размытие смещением
    vec2 offset = blurAmount * 5.0 / OutSize;
    vec4 blurred = (
        texture(MainSampler, texCoord + vec2(offset.x, 0.0)) +
        texture(MainSampler, texCoord - vec2(offset.x, 0.0)) +
        texture(MainSampler, texCoord + vec2(0.0, offset.y)) +
        texture(MainSampler, texCoord - vec2(0.0, offset.y))
    ) / 4.0;

    fragColor = mix(color, blurred, blurAmount);
}
```

### Шаг 3: Добавьте проход в transparency.json

Добавьте новый проход в массив `passes` (перед финальным blit):

```json
{
    "_comment": "My custom blur effect",
    "fragment_shader": "shader_selector:post/my_effect",
    "vertex_shader": "minecraft:core/screenquad",
    "inputs": [
        {
            "sampler_name": "Main",
            "target": "swap"
        },
        {
            "sampler_name": "Data",
            "target": "data"
        }
    ],
    "output": "final"
}
```

### Шаг 4: Команда для управления новым эффектом

```mcfunction
# Включить размытие (green=250)
# ARGB = -67239936 + 250*256 + 255 = -67175681 + 255...
# Проще: -67239936 + 64000 + value = -67175936 + value
# value=255: -67175936 + 255 = -67175681
execute as @a at @s run particle entity_effect{color:-67175681} ^ ^ ^2

# Выключить размытие
# value=0: -67175936
execute as @a at @s run particle entity_effect{color:-67175936} ^ ^ ^2
```

> **Совет:** Обратите внимание на `target` в transparency.json — это имена render target'ов. Вход вашего шейдера должен быть выходом предыдущего прохода. Выход — один из определенных target'ов (`final`, `swap`, `swap2`). Последний проход (blit) должен писать в `minecraft:main`.

---

## Разбор примера: shader.fsh

Встроенный пример демонстрирует два эффекта:

```glsl
void main() {
    // 1. ПОВОРОТ ЭКРАНА
    float rotationAmount = readChannel(EXAMPLE_ROTATION_CHANNEL);  // 0.0–1.0
    float angle = radians(rotationAmount * 360.0);                 // 0–360 градусов

    // Применяем матрицу вращения к UV-координатам
    vec2 uv = (texCoord - 0.5) * OutSize;
    uv *= mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
    uv = uv / OutSize + 0.5;

    fragColor = texture(MainSampler, uv);

    // За пределами экрана — показываем размытую версию
    if (uv.x < 0. || uv.x > 1. || uv.y < 0. || uv.y > 1.) {
        fragColor = texture(BlurSampler, (uv - 0.5)*sqrt(0.5) + 0.5);
    }

    // 2. ЧЕРНО-БЕЛЫЙ ФИЛЬТР
    vec3 greyscale = vec3(dot(fragColor.rgb, vec3(0.2126, 0.7152, 0.0722)));
    float greyscaleAmount = readChannel(EXAMPLE_GREYSCALE_CHANNEL);  // 0.0–1.0
    fragColor.rgb = mix(fragColor.rgb, greyscale, greyscaleAmount);  // Плавное смешивание
}
```

---

## Пайплайн рендеринга (transparency.json)

Проходы выполняются последовательно:

| # | Шейдер | Что делает | Вход | Выход |
|---|--------|------------|------|-------|
| 1 | `blit` | Копирует data-текстуру в swap | `data` | `data_swap` |
| 2 | `data` | Читает маркеры из частиц, обновляет data | `data_swap` + `particles` | `data` |
| 3 | `remove_particles` | Убирает маркеры из слоя частиц | `particles` | `swap` |
| 4 | `transparency` | Стандартный ванильный проход прозрачности | все слои | `final` |
| 5–10 | `box_blur` x6 | Многопроходное размытие (для примера) | `final`→`swap`→... | `swap2` |
| 11 | `shader` | Применение эффектов (пример) | `final` + `data` + `swap2` | `swap` |
| 12 | `blit` | Вывод результата на экран | `swap` | `minecraft:main` |

> Проходы 1–4 — это **ядро ShaderSelector**, их не нужно трогать. Проходы 5–12 — пример, который можно заменить на свои эффекты.

---

## Отладка

В `shader.fsh` есть встроенный режим отладки. Раскомментируйте строку:

```glsl
#define DEBUG
```

Это покажет содержимое data-текстуры в левом верхнем углу экрана (увеличенное в 4 раза). Столбец 0 показывает сырые RGBA-значения маркеров, остальные столбцы — дробную часть декодированных float-значений.

---

## Ограничения и нюансы

1. **Количество каналов** ограничено высотой data-текстуры. По умолчанию 3 строки = 2 канала (строка 0 — время). Для добавления каналов увеличивайте `height` в `transparency.json`.

2. **Диапазон значений:** Синий канал маркера (0–255) нормализуется:
   - Для операций 0, 1, 3: `value / 255.0` (0.0–1.0)
   - Для циклических операций 2, 4: `value / 256.0` (чтобы 256 значений равномерно покрывали цикл, и 0 != 256/256)

3. **Частица должна быть видна** хотя бы 1 кадр. Если она за экраном — маркер не сработает. Используйте `^ ^ ^2` (2 блока перед камерой) или `~ ~1 ~` (1 блок над игроком).

4. **Несколько маркеров одного канала** за один кадр: последний перезапишет предыдущий.

5. **Персистентность:** Data-текстура сохраняется между кадрами (`"persistent": true`), поэтому значения не сбрасываются. Однако если ресурспак перезагружен, данные теряются.

6. **DeltaTime:** Система автоматически рассчитывает delta time и пропускает обновления если `deltaTime > 0.1` (защита от лагов/пауз) или `deltaTime == 0` (два кадра в один тик).

7. **Маркер достаточно отправить один раз.** Значение сохраняется. Повторная отправка того же значения не меняет состояние (проверяется `previousColor.b == particleColor.b`).

---

## Краткая шпаргалка

### Добавить новый управляемый параметр:

1. В `marker_settings.glsl`: определить `#define MY_CHANNEL N` и добавить `ADD_MARKER(...)` в `LIST_MARKERS`
2. В `transparency.json`: увеличить `height` data-текстур если нужно
3. В своем шейдере: `float value = readChannel(MY_CHANNEL);`
4. Вычислить ARGB: `-67239936 + green * 256 + value`
5. В датапаке: `particle entity_effect{color:<ARGB>} ^ ^ ^2`

### Минимальный шейдер:

```glsl
#version 330

uniform sampler2D MainSampler;
uniform sampler2D DataSampler;

#moj_import <shader_selector:marker_settings.glsl>
#moj_import <shader_selector:utils.glsl>
#moj_import <shader_selector:data_reader.glsl>

in vec2 texCoord;
out vec4 fragColor;

void main() {
    float myValue = readChannel(MY_CHANNEL);
    fragColor = texture(MainSampler, texCoord);
    // ... ваш эффект с использованием myValue ...
}
```

### Быстрый тест из чата:

```
/particle entity_effect{color:-67174913} ~ ~1 ~    <- greyscale ON
/particle entity_effect{color:-67175168} ~ ~1 ~    <- greyscale OFF
/particle entity_effect{color:-67175616} ~ ~1 ~    <- rotation 90°
/particle entity_effect{color:-67175680} ~ ~1 ~    <- rotation 0°
/particle entity_effect{color:-67175296} ~ ~1 ~    <- smooth rotation 180°
/particle entity_effect{color:-67175424} ~ ~1 ~    <- smooth rotation 0°
```

