# Градиентная амёба

- Кодовое имя: **«Градиентная амёба»**
- Статус: production implementation
- Зафиксировано: 2026-07-12

## Коротко

«Градиентная амёба» — это индикатор записи размером 30 x 30 логических
пикселей. Он превращает реальный спектр голоса в одну мягкую замкнутую
мембрану:

- красное тело и светлая окантовка деформируются как единое целое;
- форма имеет несколько крупных выпуклостей и впадин, а не отдельные столбики;
- движение определяется фонетическими изменениями голоса, а не случайным
  шумом или автономным вращением;
- цветовой градиент, локальная яркость контура и внутренние следы реагируют на
  тот же звук;
- при тишине всё точно возвращается к маленькому кругу и перестаёт
  перерисовываться.

Итоговый эффект складывается из четырёх независимых слоёв:

1. production FFT-анализатора;
2. stateful audio-to-shape mapper с temporal whitening;
3. аналитической критически затухающей пружины;
4. многопроходного Flutter painter с градиентом, glow и историей контуров.

## Где находится реализация

| Файл | Ответственность |
|---|---|
| `lib/services/audio_spectrum_analyzer.dart` | PCM16 -> FFT -> 12 полос, level, flux и точный sample timestamp |
| `lib/services/recording_membrane.dart` | mapper, Fourier-геометрия, legacy A/B mapping и аналитическая пружина |
| `lib/widgets/dot_indicator/recording_dot.dart` | lifecycle mapper'а, sequence gating, ticker, история и painter |
| `tool/membrane_lab.dart` | offline A/B-прогон реальных WAV, метрики и артефакты |
| `tool/membrane_lab_renderer_test.dart` | точный PNG через production Flutter painter |
| `test/services/recording_membrane_test.dart` | детерминизм, diversity, bounds, silence и adversarial input |
| `test/dot_indicator_test.dart` | геометрия, пружина, continuity и widget lifecycle |

Общий аудиопайплайн и его safety-инварианты описаны отдельно в
`docs/architecture/audio_spectrum_visualizer.md`. Эта заметка фиксирует именно
визуальный алгоритм «Градиентной амёбы».

## Полный data flow

```text
PCM16 LE mono, 16 kHz
  -> AudioSpectrumAnalyzer
     -> FFT 512 samples, Hann window
     -> hop 256 samples
     -> публикация раз в два hop: 32 ms / 31.25 FPS
     -> AudioSpectrumFrame
        - 12 logarithmic bands
        - level
        - positive spectral flux
        - activityDb
        - sequence
        - endSampleExclusive
  -> RecordingDot принимает каждый sequence ровно один раз
  -> RecordingMembraneMapper формирует 11 target coefficients
  -> RecordingMembraneDynamics пружинит position/velocity к target на vsync
  -> RecordingMembraneModel восстанавливает 96 радиусов
  -> RecordingMembranePainter рисует material stack
```

Анализатор остаётся только наблюдателем. Он не изменяет PCM, не участвует в
финализации записи и не может сломать транскрипцию. При недоступном спектре
индикатор получает только scalar level и остаётся симметричным кругом.

## Представление формы

Вместо хранения 96 независимых точек используется только 11 Fourier
коэффициентов:

```text
[base, cos1, sin1, cos2, sin2, ... cos5, sin5]
```

Текущие константы:

| Параметр | Значение |
|---|---:|
| Spatial modes | 1...5 |
| Coefficients | 11 |
| Contour samples | 96 |
| Minimum center radius | 3.2 px |
| Maximum center radius | 12.8 px |
| Canvas | 30 x 30 px |

Для sample `s`:

```text
theta[s] = -pi/2 + s * 2*pi/96

radius(theta) = base
              + sum(k=1..5,
                    cosK * cos(k*theta)
                  + sinK * sin(k*theta))
```

Угол начинается сверху и идёт по окружности. Пять spatial modes дают крупные
непрерывные складки, но математически не позволяют форме превратиться в
мелкий «шерстяной ёжик».

96 точек соединяются обычным замкнутым `Path.lineTo`. Низкочастотный Fourier
basis уже является spatial low-pass filter, поэтому дополнительные local max,
Gaussian blur геометрии или cubic control points не нужны.

Перед отрисовкой применяется только shrink-only safety scale, если
консервативная сумма амплитуд могла бы пересечь диапазон 3.2...12.8. Тихая
форма никогда искусственно не растягивается до полного размера.

## Stateful audio-to-shape mapper

### 1. Время

Обычный шаг mapper'а:

```text
defaultDt = 2 * hopSize / 16000 = 0.032 s
```

Переданный `dt` ограничивается диапазоном `1/240...0.25 s`. Production widget
вычисляет его через разницу `AudioSpectrumFrame.sequence`, поэтому пропущенный
UI rebuild не замедляет аудиовремя. Невалидный, бесконечный или неположительный
`dt` заменяется на 32 ms.

### 2. Базовый радиус

```text
base = 6.0 + 2.0 * level^1.15
```

Степень больше единицы специально ослабляет whole-body scaling на обычной
речи. Основной feedback должен идти от локальных складок, а не от простого
увеличения круга.

Если спектра нет, `spectrumMix == 0` или `level == 0`, все AC coefficients
равны нулю. Получается геометрически чистый круг с тем же base formula.
Mapper при этом не обновляет и не сбрасывает slow bands или `colorPhase`.

Важно: scalar fallback с ненулевым level остаётся кругом по геометрии, но
material painter всё ещё может рисовать gradient/glow и замороженную history,
потому что его activity включает `0.30 * level`. Полностью тихий fallback
(`level == 0`) отключает optional material passes; radial body и final rim
рисуются всегда и сохраняют последнюю color phase.

### 3. Нормализация 12 полос

```text
energy[i] = clamp(band[i], 0, 1)^0.90
```

При первом spectrum frame медленный envelope инициализируется как:

```text
slow[i] = 0.72 * energy[i]
```

Это делает onset заметным, но не создаёт full-scale cold-start spike.

### 4. Temporal whitening

Главная причина, почему прежняя форма выглядела одной и той же: устойчивый
спектральный наклон конкретного голоса всегда проецировался в один сектор, а
каждый кадр затем нормализовался почти до полного reach.

«Градиентная амёба» разделяет постоянный тембр и новые фонетические события:

```text
absolute[i] = energy[i] - mean(energy)

residual[i] = energy[i] - slowPrevious[i]
noveltySignal[i] = residual[i] - mean(residual)

slowAlpha = 1 - exp(-dt / 0.52s)
slow[i]  += (energy[i] - slow[i]) * slowAlpha

shape[i] = 0.30 * absolute[i]
         + 0.70 * 2.50 * noveltySignal[i]
```

`absolute` сохраняет широкую форму на протяжной гласной. `novelty` заставляет
складки перемещаться и менять конфигурацию на реальных фонетических
изменениях. Обе компоненты zero-mean, поэтому равномерный broadband input
остаётся кругом.

Порядок существенен: `residual` и `novelty` вычисляются по **предыдущему**
slow envelope. Текущее значение `energy` попадает в envelope только после
расчёта diagnostic signals и влияет на следующий audio frame.

Диагностические величины:

```text
contrast = RMS(absolute)
novelty  = RMS(noveltySignal)
```

### 5. Noise gate

```text
meaningfulVariation = max(0.24 * contrast, novelty)
gateInput = clamp((meaningfulVariation - 0.006) / 0.045, 0, 1)
noiseGate = gateInput^2 * (3 - 2*gateInput)
```

Это обычный smoothstep. Его задача — не дать почти плоскому спектру или
floating-point noise превратиться в видимую деформацию.

### 6. Spectral centroid и цвет

```text
highBandShare = sum(energy[6..11]) / sum(energy[0..11])
centroid = sum(energy[i] * i/11) / sum(energy)
targetColorPhase = -pi/2 + 2*pi*centroid
```

Centroid использует порядковый индекс уже логарифмической полосы, а не
физическую частоту в герцах.

Поворот к target идёт по кратчайшему пути на окружности:

```text
colorTau = 0.20s * (1 - 0.42*flux)
colorAlpha = 1 - exp(-dt / colorTau)
colorPhase += wrapped(targetColorPhase - colorPhase) * colorAlpha
```

Цветовой акцент поэтому следует за спектральным центром быстрее на transient,
но не вращается сам по себе. Оборачивается только phase delta; накопленная
`colorPhase` не принудительно нормализуется в диапазон `[-pi, pi]`.

### 7. Fourier projection

Для каждой из пяти мод вычисляется real DFT:

```text
cos[k] = 2/12 * sum(shape[i] * cos(k*bandAngle[i]))
sin[k] = 2/12 * sum(shape[i] * sin(k*bandAngle[i]))
```

Текущие веса:

| Mode | Weight | Смысл |
|---:|---:|---|
| 1 | 0.06 | почти подавлена, чтобы форма не читалась как смещённый круг |
| 2 | 0.72 | крупные парные складки |
| 3 | 0.90 | основная органическая асимметрия |
| 4 | 0.92 | дополнительные широкие детали |
| 5 | 0.62 | разнообразие без мелких зубцов |

Transient drive:

```text
transient = clamp(0.62*flux + 0.38*highBandShare, 0, 1)

mode4Boost = 1 + 0.35*transient
mode5Boost = 1 + 0.55*transient
```

Итоговый DFT scale также умножается на `noiseGate` и `spectrumMix`.

### 8. Амплитуда и soft limiter

```text
rawBound = sum(k=1..5, hypot(cos[k], sin[k]))

gain = 42.0 * level^0.56 * (0.82 + 0.30*flux)
requestedReach = rawBound * gain

availableReach = max(0,
    min(12.8 - base, base - 3.2) - 0.3)

actualReach = availableReach
            * tanh(requestedReach / availableReach)

coefficientScale = actualReach / rawBound
```

Если `availableReach <= 0`, `actualReach = 0`. Если `rawBound <= 1e-9`,
`coefficientScale = 0`. Локальная реализация `tanh` сразу возвращает 1 для
аргумента `>= 20`, чтобы не вычислять ненужную экспоненту.

`0.3 px` — запас для динамики. `tanh` почти линейна на малых сигналах и мягко
сжимает только около границы окна. Это принципиальное отличие от старого
алгоритма: каждый ненулевой кадр больше не растягивается до одного и того же
full-size silhouette.

`RecordingMembraneTarget` возвращает immutable validated coefficients и
диагностику `level`, `flux`, `contrast`, `novelty`, `highBandShare`,
`colorPhase`, `requestedReach`, `actualReach`. У него есть getter:

```text
activity = clamp(0.30*level + 0.45*novelty/0.12 + 0.25*flux, 0, 1)
```

Painter этот getter сейчас не использует: он отдельно нормализует novelty до
`[0,1]`. Поэтому при `novelty > 0.12` getter и painter activity могут немного
различаться; визуальным контрактом является формула painter'а ниже.

## Пружина и временная плавность

`RecordingMembraneDynamics` хранит position, target и velocity для всех 11
коэффициентов. Новый audio frame заменяет только target. Текущие position и
velocity не сбрасываются.

Каждый coefficient использует точное аналитическое решение пружины:

| Параметр | DC/base | Modes 1...5 |
|---|---:|---:|
| Angular frequency | 22 s^-1 | 22 s^-1 |
| Damping ratio | 1.0 | 1.0 |

То есть итоговая версия критически затухающая: без overshoot и без
микрорывков от перезапуска tween.

Для каждого шага при текущем `zeta = 1` используется точное решение:

```text
d = position - target
decay = exp(-omega*dt)
q = velocity + omega*d

nextD = (d + q*dt) * decay
nextVelocity = (velocity - omega*q*dt) * decay
nextPosition = target + nextD
```

В коде сохранена также точная underdamped branch, но с текущим damping ratio
она не исполняется.

Инварианты:

- реальный elapsed time интегрируется аналитически;
- ordinary frame вплоть до 250 ms включительно не меняет скорость визуального
  времени;
- gap больше 250 ms означает resume/background и сразу snap'ает к свежему
  target вместо проигрывания устаревшей анимации;
- rest condition: `abs(position-target) < 0.002 px` и
  `abs(velocity) < 0.02 px/s` для каждого coefficient;
- после rest position точно равна target, velocity точно равна нулю, ticker
  останавливается.

## Widget lifecycle и sequence gating

Один `RecordingMembraneMapper` живёт столько же, сколько один `RecordingDot`.
Whitening state нельзя пересчитывать при каждом произвольном Flutter rebuild.

Production правила:

1. spectrum frame принимается только если изменился `sequence`;
2. повторные rebuild'ы с тем же sequence не двигают mapper;
3. `dt = sequenceDelta * 32 ms`;
4. уменьшение sequence при **непрерывно доступном spectrum** означает новый
   analyzer generation: mapper reset, visual history clear;
5. unavailable spectrum ставит `_hadSpectrum = false`, но не сбрасывает mapper,
   последний sequence или history; после fallback более низкий sequence не
   попадает в reset branch;
6. переход spectrum <-> scalar fallback меняет только target — текущая
   position остаётся непрерывной;
7. новый target запускает один vsynced `Ticker`, если он ещё не работает;
8. первый ticker tick после запуска считается равным `1/60 s`, затем
   используется реальный elapsed time;
9. `colorPhase` не является spring coefficient и обновляется сразу при новом
   audio frame;
10. новый экземпляр `RecordingDot` получает совершенно чистый mapper/history.

Это защищено отдельным widget test: двадцать unrelated rebuild'ов с одним
sequence не изменяют coefficients.

## История мембраны

Внутреннее «поле» — не процедурная сетка. Это реальные прошлые
`_dynamics.snapshot`, то есть уже пружинные render states, а не analyzer frames
и не mapper targets.

| Параметр | Значение |
|---|---:|
| Sampling interval | 48 ms |
| Capacity | 7 snapshots |
| Используемые indices | 0, 1, 3, 5 |
| Примерный возраст | 0, 48, 144, 240 ms |

Каждый delayed contour строится так:

```text
historyRadius = max(1.8,
    currentBase - inset[layer]
  + scale[layer] * (oldRadius - oldBase))
```

| Layer | Inset | Scale | Stroke | Base alpha |
|---:|---:|---:|---:|---:|
| 0 | 0.65 | 0.86 | 0.62 | 0.24 |
| 1 | 1.30 | 0.68 | 0.54 | 0.17 |
| 2 | 2.05 | 0.50 | 0.46 | 0.11 |
| 3 | 2.80 | 0.33 | 0.40 | 0.07 |

Фактическая alpha умножается на activity. Все history paths клипуются внешней
формой и рисуются через `BlendMode.screen`. Optional material passes исчезают,
когда текущая target audio activity становится `<= 0.01`; пружина в этот момент
ещё может возвращаться к кругу. Сам spring rest историю не очищает — snapshots
замерзают до следующего движения. После ticker gap больше 250 ms история
очищается.

Sampling зависит от render ticker. Даже если один frame перескочил несколько
интервалов по 48 ms, синтезируется не серия пропущенных состояний, а максимум
один новый snapshot; accumulator затем берётся по modulo 48 ms.

## Material stack painter'а

### Общая activity

```text
safeNovelty = clamp(novelty / 0.12, 0, 1)
activity = clamp(
    0.30*level
  + 0.45*safeNovelty
  + 0.25*flux,
  0, 1)
```

### Локальная реакция края

По окружности создаётся 24 angular stops плюс дублированный seam stop, то есть
25 цветов. Берётся каждый четвёртый из 96 contour samples. Для каждого stop:

```text
edge = clamp(
    0.55 * abs(radius - base) / 4.8
  + 0.35 * abs(localCoefficientVelocity) / 24
  + 0.10 * flux,
  0, 1)
```

`localCoefficientVelocity` — raw periodic Fourier velocity и включает DC/base
velocity. Edge brightness вычисляется из локальной деформации и скорости, но
затем весь sweep shader вместе с hue и brightness поворачивается на
`colorPhase`. Поэтому при ненулевой phase световой максимум пространственно
сдвинут относительно исходного geometry sector — это точное текущее поведение,
а не идеально совмещённая local-lighting model.

Palette строится из theme `fillColor` в HSL:

```text
warm: hue -15°, saturation *1.08, lightness +0.16
cool: hue +34°, saturation *1.04, lightness +0.13
chroma(theta) = lerp(warm, cool, 0.5 + 0.5*cos(theta))
```

В текущей теме `fillColor = errorBg`, `strokeColor = textOnPrimary`; поэтому
результат выглядит красно-кораллово-розовым, но эти конкретные RGB не
захардкожены. Hue берётся по modulo 360°, saturation и lightness всегда
clamp'ятся в `[0,1]`.

### Порядок отрисовки

1. **Outer glow** — только при `activity > 0.01`:
   - stroke 1.8 px;
   - round joins/caps;
   - sweep palette, повернутая на `colorPhase`;
   - blur sigma 0.35;
   - glow alpha `0.07 + 0.11*edge`.

2. **Тело** — ровная глубокая поверхность без radial gradient:
   - hue берётся из `fillColor`;
   - saturation `*0.96`;
   - lightness `*0.42`;
   - alpha 0.99.

3. **Audio impact waves** — причинные волны, clipped текущим outer path:
   - origin смещён от центра по направлению изменения Fourier target;
   - front распространяется как `0.55 + 1.72*baseRadius*progress`;
   - ellipse eccentricity в painter ограничена диапазоном `0.08...0.23`;
   - modes 2 и 3 дают фронту мягкую деформацию до 9%, но не вращают его
     автономно;
   - тёмная trailing trough: lag 1.20 px, width 1.42 px, alpha `0.18*E`,
     `BlendMode.multiply`;
   - только у сильнейшего текущего impact есть один слабый secondary front:
     lag 2.45 px, width 0.50 px, alpha `0.06*E`;
   - primary crest состоит из glow (`1.74 px`, `0.18*E`, blur 0.32) и core
     (`0.84 px`, `0.64*E`), оба через `BlendMode.screen`;
   - crest — широкая направленная дуга, а не равномерное sonar-кольцо;
   - warm/magenta chroma вдоль дуги выводится из `fillColor`, `strokeColor` и
     сохранённого `colorPhase`.

   Здесь `E` — уже включающий strength envelope:

   ```text
   p       = clamp(age / lifetime, 0, 1)
   attack  = smoothstep(clamp(p / 0.07, 0, 1))
   release = smoothstep(clamp((1 - p) / 0.24, 0, 1))
   E       = strength * attack * release * exp(-0.45*p)
   ```

   Перед paint слабые события получают perceptual compensation
   `strength^-0.24`: при strength 0.40 это примерно `x1.25`, а при 0.90 —
   только `x1.03`. Поэтому обычная речь читается, но сильные impacts почти не
   становятся ярче.

   В первые миллисекунды impact дополнительно рисуется мягкая dimple с
   `exp(-age/0.12)` и светлым crescent. Она быстро исчезает и не остаётся
   тёмным «глазом» в центре.

4. **Inner membrane band**:
   - current outer path ещё раз;
   - stroke 1.35 px;
   - clipped, поэтому видна только внутренняя половина;
   - `BlendMode.screen`;
   - local alpha `0.10 + 0.12*edge`.

5. **Один history contour** — приблизительно 144 ms назад:
   - inset 1.60 px;
   - деформация `*0.52`;
   - width 0.38 px;
   - alpha `0.055*activity`, а при живом impact дополнительно `*0.40`, чтобы
     delayed outline не превращал волну во вложенные кольца.

6. **Final rim**:
   - stroke 1.0 px;
   - round joins/caps;
   - color `lerp(chroma, strokeColor, 0.46 + 0.49*edge)`;
   - alpha `0.74 + 0.24*edge`.

7. **Impact/rim contact** — когда elliptical front касается текущей границы:
   - hit считается по elliptical distance с sigma 0.68 px;
   - 96 значений сворачиваются в 24-stop continuous sweep, поэтому нет
     бусинок из отдельных line segments;
   - glow/core widths 1.82/0.82 px, максимальные alpha 0.13/0.27;
   - эта подсветка меняет только свет, но не outer geometry.

Canvas всегда клипуется до 30 x 30. Visual wrapped в `RepaintBoundary` и
`IgnorePointer`; painter возвращает `hitTest == false`. Эффект не меняет hit
region индикатора и не перехватывает мышь.

Число draw calls теперь зависит от числа живых impacts, но painter отображает
не больше двух primary fronts и одного secondary front. Нет `saveLayer`,
`PathMetric`, fragment shader, случайного noise или вечной анимации.

Painter при создании глубоко валидирует и копирует coefficients, velocity и
каждый history snapshot. Impact snapshots immutable. `shouldRepaint` сравнивает
цвета, все audio/material scalars, geometry/history lists и все поля impacts,
поэтому старый и новый delegate не разделяют mutable buffers.

### Causal impact controller

`RecordingMembraneImpactController` вызывается только на новом spectrum
sequence; vsync лишь увеличивает age уже созданных волн. Drive:

```text
shapeKick = clamp(rms(delta Fourier coefficients) / 0.45, 0, 1)
levelGate = smoothstep(clamp((level - 0.04) / 0.22, 0, 1))
drive     = levelGate * (0.45*flux + 0.35*novelty + 0.20*shapeKick)
```

- trigger 0.30, rearm 0.24, refractory 120 ms;
- lifetime 550 ms;
- не больше двух живых impacts;
- strength начинается с 0.40 и нелинейно доходит до 1.0;
- origin radius ограничен 0.40 base radius;
- direction детерминированно выводится из strongest Fourier-target delta, а
  `colorPhase` используется как fallback/blend;
- random, idle oscillator и continuous forcing отсутствуют.

Ticker работает, пока движется outer spring **или** жив хотя бы один impact.
Impacts полностью reset'ятся при rollback spectrum sequence, пропуске больше
250 ms и уходе в scalar fallback. Поэтому никакая волна не может жить после
завершения recording session.

### Retune под обычную речь, 2026-07-12

Первый impact gate (`trigger 0.38`, `rearm 0.18`) был слишком широко раскрыт:
на свежих речевых WAV median drive был около 0.42 и 60% active frames уже
лежали выше trigger, но после первого события controller ждал почти полной
паузы для rearm. Поэтому медианный разрыв доходил до 2.34 s, а волна была видна
лишь 24% записи.

Проверка нового gate `0.30 / 0.24 / 120 ms` на трёх последних реальных WAV:

| Recording | Duration | Impacts before -> after | Rate after | Gap med before -> after | Visible before -> after |
|---|---:|---:|---:|---:|---:|
| `recording_20260712_014003_720` | 40.10 s | 18 -> 53 | 1.32/s | 2.34 -> 0.67 s | 23.6% -> 58.7% |
| `recording_20260712_014208_943` | 31.71 s | 19 -> 31 | 0.98/s | 1.38 -> 0.93 s | 30.9% -> 49.9% |
| `recording_20260712_013931_300` | 25.97 s | 20 -> 39 | 1.50/s | 0.99 -> 0.61 s | 37.8% -> 66.7% |

Это остаётся Schmitt crossing, а не periodic retrigger: одинаковый held input
всё ещё создаёт только один impact. Более агрессивный adaptive cadence давал
79...86% coverage и был отвергнут как почти непрерывная анимация.

## Legacy baseline: важная ловушка

Production widget использует только `RecordingMembraneMapper.map(...)`.
`RecordingMembraneModel.coefficientsFor(...)` сохранён ради A/B и старых
геометрических fixtures. Его нельзя случайно начать тюнить в ожидании, что
изменится live indicator.

Legacy mapping:

```text
weights = [0.30, 1.00, 0.90, 0.65, 0.40]
energy = band^0.90
contrastGate = smoothstep((contrast - 0.02) / 0.10)

reach = 4.8 * level^0.55
      * contrastGate
      * (0.90 + 0.10*flux)
      * spectrumMix

scale = min(reach, availableReach) / acBound
```

Именно последняя hard normalization почти каждый реальный active frame
растягивала до похожего размера и была одной из причин voice-locked blob.

Ещё одна ловушка API: статический
`RecordingMembranePainter.contourRadii(...)` делегирует этому legacy mapping.
Live `paint()` получает уже готовые stateful coefficients и вызывает только
`radiiFromCoefficients(...)`.

## Offline-lab

Лаборатория нужна, чтобы не делать медленный цикл «изменить код -> собрать
приложение -> записать голос -> объяснить, что опять не так». Она запускает тот
же production analyzer, mapper, Fourier model и spring на сохранённых WAV.

### Запуск

```powershell
dart run tool\membrane_lab.dart

dart run tool\membrane_lab.dart `
  --input "C:\path\to\recordings" `
  --longest 3 `
  --out build\membrane_lab `
  --fps 60
```

Параметры:

| Option | Default | Назначение |
|---|---|---|
| `-i`, `--input` | `%APPDATA%\com.example\open_vibrance\recordings` | WAV или directory; можно повторять |
| `--longest` | 3 | число самых длинных совместимых WAV |
| `-o`, `--out` | `build\membrane_lab` | output directory |
| `--fps` | 60 | simulation FPS, допустимо 30...120 |
| `--no-png` | false | не запускать Flutter renderer |
| `-h`, `--help` | — | usage |

Поддерживается только RIFF/WAVE PCM16 LE, mono, 16 kHz. Directories обходятся
рекурсивно, пути deduplicate'ятся без учёта регистра, recordings сортируются по
реальному PCM sample count. Несовместимые старые stereo/44.1 kHz WAV
игнорируются при discovery.

### Точная симуляция

1. PCM передаётся production analyzer порциями по 4096 bytes.
2. Время каждого spectrum event берётся из
   `endSampleExclusive / sampleRate`, а не угадывается по wall clock.
3. Перед каждым output frame обе пружины и causal impact controller
   продвигаются точно до всех промежуточных spectrum events; mapper retarget и
   `processTarget` происходят на точном analyzer timestamp, после чего система
   доходит до output timestamp.
4. Candidate — текущий stateful mapper.
5. Baseline — старый stateless mapping, но пропущенный через текущую общую
   пружину. Это сравнение mapping'ов, а не byte-exact историческая версия всего
   старого renderer'а.
6. После WAV добавляется 750 ms silence tail для проверки settling.
7. Метрики считают только frames с `activityDb >= -62 dB`.

### Артефакты

```text
build/membrane_lab/
  summary.json
  summary.md
  replay.html
  render_frames.json
  impact_frames.json
  contact-sheet.png
  impact-grid.png
  recordings/
    <recording>/
      trace.json
      points.ndjson
      contact-sheet.svg
```

- `points.ndjson` содержит каждый кадр и оба массива из 96 радиусов;
- `replay.html` полностью локальный, использует сохранённые точки и не
  пересчитывает модель в JavaScript; его material rendering — browser
  approximation;
- `contact-sheet.png` рисует candidate настоящим production Flutter painter;
- `impact-grid.png` — exact production-painter сетка 8 x 3: low, medium и high
  реальные emitted impacts, восемь возрастов каждого события;
- в каждой PNG-паре legacy mapping слева, «Градиентная амёба» справа;
- `render_frames.json` хранит coefficients, velocity, novelty, color phase и
  семь history states вместе с impact snapshots для representative frames;
- `impact_frames.json` хранит выбранные emission id/strength/time, requested и
  actual offsets, а также полный painter payload каждой клетки;
- WAV никуда не копируются.

Representative frames выбираются детерминированно: половина — chronological
quantiles, затем maximum-range и greedy farthest shapes в normalized contour
space с минимальным интервалом 350 ms.

PNG является единственным pixel-faithful production rendering. SVG и HTML
намеренно остаются переносимыми приближениями.

Без `--no-png` основной Dart process запускает отдельный Flutter widget test,
ждёт, пока размер PNG стабилизируется шесть polling cycles, и завершает его
process tree. С `--no-png` весь прогон остаётся pure Dart.

### Основные метрики

| Metric | Определение |
|---|---|
| Range | `max(radius) - min(radius)` |
| Motion | RMS разницы радиусов соседних active frames |
| Acceleration | RMS второй разницы трёх соседних frames |
| Adjacent similarity | cosine mean-centered L2-normalized contours |
| Radial jump | максимальное pointwise смещение между соседними frames |
| Prototype similarity | mean cosine к среднему normalized contour |
| Orientation concentration | circular resultant положительной деформации; 1 = форма прибита к одному направлению |
| Orientation bins | число занятых 30° секторов из 12 |
| Prominent peaks | prominence `max(0.08*range, 0.15 px)`, valleys по 12 samples |
| Modes 4+5 share | доля суммы Fourier magnitudes мод 4 и 5 |
| Range/level correlation | Pearson correlation range и analyzer level |
| Impact rate | emitted impacts / исходная WAV duration |
| Impact gap | median, P90 и max разрыва между emissions |
| Drive distribution | P50/P75/P90 по active speech frames и доля выше текущего trigger |
| Visible share | доля всех render frames, где жив хотя бы один impact |

Temporal метрики текущего lab корректно интерпретируются для production run на
60 FPS. При 30 FPS нынешний `< 0.03 s` adjacency filter исключает nominal
33.3 ms пары и возвращает пустые default values; это известное ограничение lab,
а не production renderer'а.

### Известные ограничения lab

- output directory перед запуском не очищается, поэтому при изменении набора
  inputs в нём могут остаться старые recording subdirectories;
- `summary.json` содержит абсолютные локальные пути исходных WAV;
- schema пока не хранит WAV/source hashes или deterministic artifact hashes;
- нет automatic pass/fail gate: метрики — диагностика, визуальная приёмка всё
  ещё делается по replay и production PNG;
- `trace.json` содержит aggregate summary, а полный per-frame trace находится
  в `points.ndjson`;
- browser replay не проигрывает и не встраивает исходное аудио.

## Зафиксированный real-recording результат

Финальный прогон сделан на 60 FPS:

| Recording | Duration | Active frames |
|---|---:|---:|
| `recording_20260711_231639_081` | 119.648 s | 4,716 |
| `recording_20260711_133130_756` | 88.738 s | 5,322 |
| `recording_20260304_205621_358` | 82.658 s | 4,957 |

Главное сравнение legacy mapping -> «Градиентная амёба»:

| Metric | Legacy | Градиентная амёба |
|---|---:|---:|
| Orientation concentration | 0.986...0.988 | 0.244...0.509 |
| Occupied orientation bins | 3...4 / 12 | 12 / 12 |
| Prototype similarity | 0.898...0.930 | 0.280...0.434 |
| Frames with 4+ peaks | 1.9...3.9% | 41.2...49.7% |
| Modes 4+5 share | 18.7...19.7% | 39.0...42.2% |
| Median motion | 0.050...0.057 px/frame | 0.118...0.130 px/frame |
| P90 radial range | 4.858...6.277 px | 4.907...5.856 px |

То есть форма перестала быть одним voice-locked blob, использовала все сектора
и стала примерно вдвое активнее. Цена этого решения тоже зафиксирована честно:

- median radial range на этих файлах ниже legacy примерно на 7...19%;
- acceleration выше примерно в 1.9...2.4 раза;
- P99 pointwise jump вырос с 0.369...0.403 до 0.569...0.812 px;
- adjacent similarity снизилась с 0.993...0.996 до 0.950...0.961.

Именно поэтому финальная пружина была замедлена до `omega = 22` и сделана
критически затухающей. Она сохраняет заметно более живой feedback, но убирает
ранние микрорывки и overshoot.

## Что нельзя случайно сломать

1. Не возвращать per-frame normalization до полного available reach.
2. Не убирать temporal whitening или превращать novelty в случайное движение.
3. Не обновлять mapper на unrelated Flutter rebuild — только на новый sequence.
4. Не сбрасывать spring velocity при retarget.
5. Не переносить whitening на vsync ticker: результат станет зависеть от FPS.
6. Не придумывать асимметрию в scalar fallback без spectrum data.
7. Не хранить 96 независимых динамических точек — low Fourier modes являются
   основой spatial coherence.
8. Не рисовать историю вне current outer path.
9. Не допускать visual layer к hit testing.
10. Не связывать visual analyzer с PCM delivery или transcription finalization.

## Карта тюнинга

| Что менять | Визуальный эффект | Основной риск |
|---|---|---|
| `slowEnvelopeSeconds` вверх | более медленная смена спектральной нормы, длиннее память тембра | форма запаздывает после смены голоса/источника |
| `absoluteMix` вверх | устойчивее крупная форма на гласных | снова появляется один voice-locked silhouette |
| `noveltyBoost` вверх | больше фонетического движения | микрорывки и слишком хаотичная форма |
| modes 4/5 weights вверх | больше складок и diversity | цветок/шестерёнка |
| mode 1 вверх | сильнее directional movement | выглядит как перемещение целого круга |
| gain вверх | выше амплитуда | частая работа limiter'а, большие jumps |
| spring omega вверх | быстрее реакция | резче движение |
| damping ниже 1 | мясистый overshoot | дрожь и ringing |
| history alpha/scale вверх | сильнее внутреннее поле | грязь в 30 x 30 |
| rim white mix вверх | ярче белая окантовка | теряется coral/magenta цвет |
| glow blur/alpha вверх | более «неоновый» объект | оптическая муть и clipping |

Любой новый тюнинг сначала прогоняется через real-WAV lab. Амплитуду нельзя
оценивать отдельно от diversity, motion, acceleration и contact sheet.

## Проверка после изменений

```powershell
dart run tool\membrane_lab.dart --longest 3 --out build\membrane_lab

flutter test

flutter analyze lib\services\recording_membrane.dart `
  lib\widgets\dot_indicator\recording_dot.dart `
  test\services\recording_membrane_test.dart `
  test\dot_indicator_test.dart `
  tool\membrane_lab.dart

flutter build windows --release
```

После lab нужно проверить три вещи:

1. `summary.md`: diversity выросла не ценой clipping/jumps;
2. `contact-sheet.png`: форма остаётся крупной и органической на разных
   фонетических состояниях;
3. `impact-grid.png`: crest проходит от dimple к rim без radial wash,
   sonar-бусинок и тёмного центрального «глаза»;
4. `replay.html`: движение на реальном времени непрерывное, не выглядит
   случайным и полностью успокаивается на тишине.

## Почему название подходит

Это не эквалайзер вокруг круга и не набор независимо растущих щупалец.
Геометрия, цвет, светлая кромка и внутренние delayed sheets образуют один
мягкий объект. Спектр меняет его локальную форму, temporal novelty заставляет
складки перетекать, а градиент и rim показывают, где мембрана сейчас активнее.

Поэтому: **Градиентная амёба**.
