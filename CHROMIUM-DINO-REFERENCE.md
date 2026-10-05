# Chrome 小恐龙（T-Rex Runner）完整游戏机制技术规格

> 目标：可直接照着在 PowerShell 里逐帧复刻。
> 所有数值均来自源码原文，不使用「大约 / 类似」。
> 每条结论后标注 **文件 · 函数**。

---

## 0. 数据来源与核对状态

| 来源 | URL | 状态 |
|---|---|---|
| 目录清单 | `https://api.github.com/repos/chromium/chromium/contents/components/neterror/resources/dino_game` (ref=main) | ✅ 200，得到全部 19 个文件 |
| 当前 TS 源码 | `https://cdn.jsdelivr.net/gh/chromium/chromium@main/components/neterror/resources/dino_game/<file>` | ✅ 全部取到 |
| 旧版 `offline.js` | `.../chromium@120.0.6099.109/components/neterror/resources/offline.js` | ⚠️ 部分：jsDelivr 以 `application/javascript` 返回，`web_fetch` 拒收（"unsupported content type"）；改用 GitHub Contents API 得到 base64，取到了**文件首段 + Tail 段**，中间段被截断 |
| 旧版精灵定义 | `.../chromium@120.0.6099.109/components/neterror/resources/offline-sprite-definitions.js` | ✅ 完整（base64 全量可读） |

**取不到的 URL 及尝试记录（不要以为我凭记忆编造）：**

- `https://chromium.googlesource.com/chromium/src/+/HEAD/components/neterror/resources/dino_game/` → `TypeError: fetch failed`（该域在此环境不可达）
- `https://raw.githubusercontent.com/chromium/chromium/...` → `fetch failed`（域不可达）
- `https://cdn.statically.io/gh/...`、`https://raw.githack.com/...`、`https://r.jina.ai/...` → `fetch failed`
- `https://api.codetabs.com/v1/proxy?quest=...`、`https://api.allorigins.win/raw?url=...` → HTTP 522 / 520（代理侧超时）
- `https://github.com/chromium/chromium/blob/120.0.6099.109/.../offline.js?plain=1` → 200 但正文未包含在返回的 HTML 中（只得到 GitHub 导航外壳）
- 本机 `pwsh` 不可用：沙箱初始化报 `SetNamedSecurityInfoW failed (Win32 5): grantWrite(D:\Test_DSH)`，因此**无法在本地下载文件或解码 base64**

**因此：**第 17 节「新旧对比」中，凡标 ✅ 的行是我**逐字解码核对**过的；凡标 ❓ 的行我明确说明没有取到原文，不做断言。

---

## 1. 文件清单（`components/neterror/resources/dino_game/`，ref=main）

| 文件 | 字节 | 作用 |
|---|---|---|
| `constants.ts` | 697 | `FPS`、`DEFAULT_DIMENSIONS`、`IS_HIDPI` / `IS_MOBILE` / `IS_IOS` / `IS_RTL` |
| `dimensions.ts` | 211 | `interface Dimensions {width, height}` |
| `game_config.ts` | 1437 | `BaseConfig` / `GameModeConfig` / `Config` 接口（**无数值**） |
| `offline.ts` | 55293 | `Runner` 主控：数值默认配置、游戏循环、速度、碰撞、状态机、重开、输入 |
| `trex.ts` | 16318 | `Trex`：跳跃/下蹲/碰撞盒/动画帧/闪烁 |
| `obstacle.ts` | 7046 | `Obstacle`：移动、gap 算法、碰撞盒克隆 |
| `horizon.ts` | 12224 | `Horizon`：地平线滚动、障碍生成调度、云、夜晚模式入口 |
| `horizon_line.ts` | 3767 | `HorizonLine`：两段 600px 地面瓦片 |
| `offline_sprite_definitions.ts` | 6069 | 精灵坐标、障碍数值定义、`CollisionBox` |
| `distance_meter.ts` | 11443 | 分数显示、成就闪烁、最高分 |
| `night_mode.ts` | 5152 | 月亮/星星 |
| `cloud.ts` | 2606 | 云 |
| `background_el.ts` | 4667 | 可配置背景元素（alt 模式用） |
| `game_over_panel.ts` | 9897 | GAME OVER 文字 + 重开按钮动画 |
| `game_state_provider.ts` / `image_sprite_provider.ts` / `sprite_position.ts` / `generated_sound_fx.ts` | 小 | 依赖注入接口（无数值影响） |

**结论：数值型默认配置不在 `game_config.ts`，而是在 `offline.ts` 顶部的 `defaultBaseConfig` / `normalModeConfig` / `slowModeConfig`。**

---

## 2. 全部数值常量（逐条，带原始名字与出处）

### 2.1 `offline.ts` · `defaultBaseConfig: BaseConfig`

| 名字 | 值 |
|---|---|
| `audiocueProximityThreshold` | `190` |
| `audiocueProximityThresholdMobileA11y` | `250` |
| `bgCloudSpeed` | `0.2` |
| `bottomPad` | `10` |
| `canvasInViewOffset` | `-10` |
| `clearTime` | `3000` |
| `cloudFrequency` | `0.5` |
| `fadeDuration` | `1` |
| `flashDuration` | `1000` |
| `gameoverClearTime` | `1200` |
| `initialJumpVelocity` | `12` |
| `invertFadeDuration` | `12000` |
| `maxBlinkCount` | `3` |
| `maxClouds` | `6` |
| `maxObstacleLength` | `3` |
| `maxObstacleDuplication` | `2` |
| `resourceTemplateId` | `'audio-resources'` |
| `speed` | `6` |
| `speedDropCoefficient` | `3` |
| `arcadeModeInitialTopPosition` | `35` |
| `arcadeModeTopPositionPercent` | `0.1` |

### 2.2 `offline.ts` · `normalModeConfig: GameModeConfig`（**默认玩法用这套**）

| 名字 | 值 |
|---|---|
| `acceleration` | `0.001` |
| `audiocueProximityThreshold` | `190` |
| `audiocueProximityThresholdMobileA11y` | `250` |
| `gapCoefficient` | `0.6` |
| `invertDistance` | `700` |
| `maxSpeed` | `13` |
| `mobileSpeedCoefficient` | `1.2` |
| `speed` | `6` |

### 2.3 `offline.ts` · `slowModeConfig`（只有开启 audio cues 后勾选「slow」才生效）

| 名字 | 值 |
|---|---|
| `acceleration` | `0.0005` |
| `audiocueProximityThreshold` | `170` |
| `audiocueProximityThresholdMobileA11y` | `220` |
| `gapCoefficient` | `0.3` |
| `invertDistance` | `350` |
| `maxSpeed` | `9` |
| `mobileSpeedCoefficient` | `1.5` |
| `speed` | `4.2` |

### 2.4 `constants.ts`

| 名字 | 值 |
|---|---|
| `FPS` | `60` |
| `DEFAULT_DIMENSIONS` | `{width: 600, height: 150}` |
| `IS_HIDPI` | `window.devicePixelRatio > 1` |
| `IS_MOBILE` | `/Android/.test(ua) \|\| IS_IOS` |
| `IS_IOS` | `/CriOS/.test(ua)` |
| `IS_RTL` | `document.documentElement.dir === 'rtl'` |

### 2.5 `trex.ts` · `defaultTrexConfig: BaseTrexConfig`

| 名字 | 值 |
|---|---|
| `dropVelocity` | `-5` |
| `flashOff` | `175` |
| `flashOn` | `100` |
| `height` | `47` |
| `heightDuck` | `25` |
| `introDuration` | `1500` |
| `speedDropCoefficient` | `3` |
| `spriteWidth` | `262` |
| `startXPos` | `50` |
| `width` | `44` |
| `widthDuck` | `59` |
| `invertJump` | `false` |

### 2.6 `trex.ts` · 跳跃配置

`slowJumpConfig`（仅 `hasSlowdown` 时）

| 名字 | 值 |
|---|---|
| `gravity` | `0.25` |
| `maxJumpHeight` | `50` |
| `minJumpHeight` | `45` |
| `initialJumpVelocity` | `-20` |

`normalJumpConfig`（**默认**）

| 名字 | 值 |
|---|---|
| `gravity` | `0.6` |
| `maxJumpHeight` | `30` |
| `minJumpHeight` | `30` |
| `initialJumpVelocity` | `-10` |

> 构造函数：`this.config = Object.assign(defaultTrexConfig, normalJumpConfig)`（`trex.ts` · `constructor`）。
> 即实际生效的是 **gravity 0.6 / maxJumpHeight 30 / minJumpHeight 30 / initialJumpVelocity -10**。

### 2.7 `trex.ts` · 其他常量

| 名字 | 值 | 出处 |
|---|---|---|
| `BLINK_TIMING` | `7000` | `trex.ts` 模块级 |
| `animFrames[WAITING]` | `frames: [44, 0], msPerFrame: 1000/3` | 同上 |
| `animFrames[RUNNING]` | `frames: [88, 132], msPerFrame: 1000/12` | 同上 |
| `animFrames[CRASHED]` | `frames: [220], msPerFrame: 1000/60` | 同上 |
| `animFrames[JUMPING]` | `frames: [0], msPerFrame: 1000/60` | 同上 |
| `animFrames[DUCKING]` | `frames: [264, 323], msPerFrame: 1000/8` | 同上 |
| `msPerFrame`（字段默认值） | `1000 / FPS` = `16.666…` | `trex.ts` · 字段声明 |

派生量（`trex.ts` · `constructor`）：
```
groundYPos      = DEFAULT_DIMENSIONS.height - config.height - config.bottomPad
                = 150 - 47 - 10 = 93
yPos            = 93
minJumpHeight   = groundYPos - config.minJumpHeight = 93 - 30 = 63   // 绝对值
```

### 2.8 `obstacle.ts`

| 名字 | 值 |
|---|---|
| `maxGapCoefficient`（模块级 `let`） | `1.5` |
| `maxObstacleLength`（模块级 `let`） | `3` |

### 2.9 `horizon.ts` · `horizonConfig`

| 名字 | 值 | 备注 |
|---|---|---|
| `BG_CLOUD_SPEED` | `0.2` | 实际用于云 |
| `BUMPY_THRESHOLD` | `0.3` | **声明后未使用**（地平线用的是 `HorizonLine.bumpThreshold = 0.5`） |
| `CLOUD_FREQUENCY` | `0.5` | |
| `HORIZON_HEIGHT` | `16` | **声明后未使用** |
| `MAX_CLOUDS` | `6` | |

### 2.10 `cloud.ts` · `Config`

| 名字 | 值 |
|---|---|
| `HEIGHT` | `14` |
| `WIDTH` | `46` |
| `MIN_CLOUD_GAP` | `100` |
| `MAX_CLOUD_GAP` | `400` |
| `MIN_SKY_LEVEL` | `71` |
| `MAX_SKY_LEVEL` | `30` |

### 2.11 `night_mode.ts`

| 名字 | 值 |
|---|---|
| `PHASES` | `[140, 120, 100, 60, 40, 20, 0]` |
| `FADE_SPEED` | `0.035` |
| `HEIGHT` | `40` |
| `MOON_SPEED` | `0.25` |
| `NUM_STARS` | `2` |
| `STAR_SIZE` | `9` |
| `STAR_SPEED` | `0.3` |
| `STAR_MAX_Y` | `70` |
| `WIDTH` | `20` |
| `yPos` 初值 | `30` |
| `xPos` 初值 | `0` |

### 2.12 `distance_meter.ts`

`Dimensions` 枚举：

| 名字 | 值 |
|---|---|
| `WIDTH` | `10` |
| `HEIGHT` | `13` |
| `DEST_WIDTH` | `11` |

`Config` 枚举：

| 名字 | 值 |
|---|---|
| `MAX_DISTANCE_UNITS` | `5` |
| `ACHIEVEMENT_DISTANCE` | `100` |
| `COEFFICIENT` | `0.025` |
| `FLASH_DURATION` | `1000 / 4` = `250` |
| `FLASH_ITERATIONS` | `3` |
| `HIGH_SCORE_HIT_AREA_PADDING` | `4` |

其他：`y = 5`（`distance_meter.ts` · 字段）。

### 2.13 `horizon_line.ts`

| 名字 | 值 |
|---|---|
| `bumpThreshold` | `0.5` |

### 2.14 `game_over_panel.ts`

| 名字 | 值 |
|---|---|
| `RESTART_ANIM_DURATION` | `875` |
| `LOGO_PAUSE_DURATION` | `875` |
| `FLASH_ITERATIONS` | `5` |
| `animConfig.frames` | `[0, 36, 72, 108, 144, 180, 216, 252]` |
| `animConfig.msPerFrame` | `875 / 8` = `109.375` |
| `defaultPanelDimensions` | `{textX: 0, textY: 13, textWidth: 191, textHeight: 11, restartWidth: 36, restartHeight: 32}` |

### 2.15 `offline_sprite_definitions.ts` · `original`（障碍数值，**核心**）

文件级：

| 名字 | 值 |
|---|---|
| `maxGapCoefficient` | `1.5` |
| `maxObstacleLength` | `3` |
| `hasClouds` | `true` |
| `bottomPad` | `10` |

`obstacles[]`（按数组顺序，索引即 `getRandomNum` 的取值域）：

| # | `type` | `width` | `height` | `yPos` | `yPosMobile` | `multipleSpeed` | `minGap` | `minSpeed` | `numFrames` | `frameRate` | `speedOffset` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `cactusSmall` | 17 | 35 | 105 | — | 4 | 120 | 0 | — | — | — |
| 1 | `cactusLarge` | 25 | 50 | 90 | — | 7 | 120 | 0 | — | — | — |
| 2 | `pterodactyl` | 46 | 40 | `[100, 75, 50]` | `[100, 50]` | 999 | 150 | 8.5 | 2 | `1000/6` | `0.8` |
| 3 | `collectable` | 31 | 24 | 104 | — | 1000 | 9999 | 0 | — | — | — |

碰撞盒（相对坐标，`{x, y, width, height}`）：

- `cactusSmall`：`{0,7,5,27}`、`{4,0,6,34}`、`{10,4,7,14}`
- `cactusLarge`：`{0,12,7,38}`、`{8,0,7,49}`、`{13,10,10,38}`
- `pterodactyl`：`{15,15,16,5}`、`{18,21,24,6}`、`{2,14,4,3}`、`{6,10,4,7}`、`{10,8,6,9}`
- `collectable`：`{0,0,32,25}`

> **注意 `collectable` 的碰撞盒宽 32 > `width` 31**；且 `collectable` 只在 alt game mode 下参与（见 §11.9）。

`backgroundEl`：

```
'CLOUD': {height: 14, offset: 4, width: 46, xPos: 1, fixed: false}
backgroundElConfig: {maxBgEls: 1, maxGap: 400, minGap: 100, pos: 0, speed: 0.5, yPos: 125}
lines: [{sourceX: 2, sourceY: 52, width: 600, height: 12, yPos: 127}]
altGameOverTextConfig: {textX:32, textY:0, textWidth:246, textHeight:17, flashDuration:1500, flashing:false}
```

### 2.16 `trex.ts` · `collisionBoxes`

```js
ducking: [ new CollisionBox(1, 18, 55, 25) ]
running: [
  new CollisionBox(22, 0, 17, 16),
  new CollisionBox(1, 18, 30, 9),
  new CollisionBox(10, 35, 14, 8),
  new CollisionBox(1, 24, 29, 5),
  new CollisionBox(5, 30, 21, 4),
  new CollisionBox(9, 34, 15, 4),
]
```

### 2.17 `offline.ts` · 输入键码

```js
runnerKeycodes = {
  jump:    [38, 32],  // ArrowUp, Space
  duck:    [40],      // ArrowDown
  restart: [13],      // Enter
}
```

### 2.18 精灵表坐标（`offline_sprite_definitions.ts`，`{x, y}`）

| 精灵 | ldpi | hdpi |
|---|---|---|
| `backgroundEl` | `{86, 2}` | `{166, 2}` |
| `cactusLarge` | `{332, 2}` | `{652, 2}` |
| `cactusSmall` | `{228, 2}` | `{446, 2}` |
| `obstacle2` | `{332, 2}` | `{652, 2}` |
| `obstacle` | `{228, 2}` | `{446, 2}` |
| `cloud` | `{86, 2}` | `{166, 2}` |
| `horizon` | `{2, 54}` | `{2, 104}` |
| `moon` | `{484, 2}` | `{954, 2}` |
| `pterodactyl` | `{134, 2}` | `{260, 2}` |
| `restart` | `{2, 68}` | `{2, 130}` |
| `textSprite` | `{655, 2}` | `{1294, 2}` |
| `tRex` | `{848, 2}` | `{1678, 2}` |
| `star` | `{645, 2}` | `{1276, 2}` |
| `collectable` | `{0, 0}` | `{0, 0}` |
| `altGameEnd` | `{32, 0}` | `{64, 0}` |

所有精灵坐标在 `IS_HIDPI` 时**会先 `*2`**（各 `draw()` 内部），再加 `spritePos.x/y`。障碍的源 X 计算见 §11.4。

---

## 3. 游戏循环与时间步进

### 3.1 主循环驱动

`offline.ts` · `ScheduleNextUpdate` / `update`：

```js
scheduleNextUpdate() {
  if (!this.updatePending) {
    this.updatePending = true;
    this.raqId = requestAnimationFrame(this.update.bind(this));
  }
}
```

- 使用 `requestAnimationFrame`，**每帧最多一次 `update()`**（`updatePending` 去重）。
- `isRunning()` 返回 `!!this.raqId`（用于判断 keyup 是否应触发 `endJump`）。

### 3.2 deltaTime 计算（`offline.ts` · `update`）

```js
const now = getTimeStamp();                 // performance.now()，iOS 用 Date.now()
let deltaTime = now - (this.time || now);   // 首次调用 this.time===0 → deltaTime = 0
// ...（alt game 切模式闪光时：deltaTime 被置 0）
this.time = now;
```

**关键结论：当前版本对 `deltaTime` 没有任何上限裁剪（no clamping）。**
没有 `Math.min(deltaTime, X)`，也没有"超过 N ms 就当作固定值"的逻辑。掉帧时会一次性推进一大步。

### 3.3 「帧」换算 `framesElapsed`（唯一出现处）

`trex.ts` · `updateJump`：

```js
const msPerFrame    = animFrames[this.status].msPerFrame;  // JUMPING → 1000/60 = 16.6667
const framesElapsed = deltaTime / msPerFrame;              // = deltaTime * 0.06
```

除此之外，游戏逻辑**不做帧量化**：`distanceRan`、`currentSpeed` 的累加都用原始 `deltaTime`。
但也有三处把 `deltaTime` 换成整数像素步进：

- `obstacle.ts` · `update`：`this.xPos -= Math.floor((speed * FPS / 1000) * deltaTime)`，即 `Math.floor(speed * 0.06 * deltaTime)`
- `horizon_line.ts` · `update`：`const increment = Math.floor(speed * (FPS / 1000) * deltaTime)`
- `cloud.ts` · `update`：`this.xPos -= Math.ceil(speed)`（**没有 deltaTime**，由调用方把速度预先换算好，见 §12.1）

---

## 4. 每帧完整流程（`offline.ts` · `Runner.update`，逐行伪代码）

```
update():
  this.updatePending = false
  now = getTimeStamp()
  deltaTime = now - (this.time || now)

  // (A) alt game 模式切换闪光
  if altGameModeFlashTimer !== null:
      if altGameModeFlashTimer <= 0:
          altGameModeFlashTimer = null; tRex.setFlashing(false); enableAltGameMode()
      else:
          altGameModeFlashTimer -= deltaTime
          tRex.update(deltaTime)          // 用原 deltaTime
          deltaTime = 0                   // 本帧其余时间推进全部归零
  this.time = now

  if this.playing:
      clearCanvas()

      // (B) alt game 淡入
      if altGameModeActive && fadeInTimer <= config.fadeDuration:
          fadeInTimer += deltaTime / 1000
          canvasCtx.globalAlpha = fadeInTimer
      else:
          canvasCtx.globalAlpha = 1

      // (C) 跳跃物理
      if tRex.jumping: tRex.updateJump(deltaTime)

      // (D) 起跑保护计时
      runningTime += deltaTime
      hasObstacles = runningTime > config.clearTime        // clearTime = 3000

      // (E) 首次落地触发 intro
      if tRex.jumpCount === 1 && !playingIntro: playIntro()

      // (F) 世界滚动
      if playingIntro:
          horizon.update(0, currentSpeed, hasObstacles, false)   // deltaTime 强制 0
      else if !crashed:
          showNightMode = (isDarkMode !== inverted)
          deltaTime = !activated ? 0 : deltaTime
          horizon.update(deltaTime, currentSpeed, hasObstacles, showNightMode)

      firstObstacle = horizon.obstacles[0]

      // (G) 碰撞（只测第一个障碍）
      collision = hasObstacles && firstObstacle && checkForCollision(firstObstacle, tRex)

      // (H) a11y 音频提示（仅 audio cues 开启时）
      ...

      // (I) alt game collectable
      ...

      // (J) 距离与速度
      if !collision:
          distanceRan += currentSpeed * deltaTime / this.msPerFrame   // msPerFrame = 1000/60
          if currentSpeed < config.maxSpeed: currentSpeed += config.acceleration
      else:
          gameOver()

      // (K) 分数显示
      playAchievementSound = distanceMeter.update(deltaTime, Math.ceil(distanceRan))
      if !hasAudioCues && playAchievementSound: playSound(soundFx.SCORE)

      // (L) 夜晚模式触发器
      ...

  // (M) 尾帧
  if playing || (!activated && tRex.blinkCount < config.maxBlinkCount):
      tRex.update(deltaTime)
      scheduleNextUpdate()
```

**注意顺序**：`horizon.update()`（障碍移动/生成）发生在 `currentSpeed` 增长**之前**，所以本帧障碍用的是上一帧末的速度值。

---

## 5. 速度模型

### 5.1 初始速度

```js
// offline.ts · constructor
this.config = configParam || Object.assign({}, defaultBaseConfig, normalModeConfig);
this.currentSpeed = this.config.speed;      // = 6
```

### 5.2 每帧增长（**按帧，不按距离**）

```js
// offline.ts · update
if (!collision) {
  this.distanceRan += this.currentSpeed * deltaTime / this.msPerFrame;
  if (this.currentSpeed < this.config.maxSpeed) {
    this.currentSpeed += this.config.acceleration;    // +0.001 / 帧
  }
}
```

- 增量是**每帧固定 `+0.001`**，与 `deltaTime` 无关（掉帧不会加速）。
- 上界 `maxSpeed = 13`。
- 从 6 → 13 需要 `(13-6)/0.001 = 7000` 帧 ≈ **116.67 秒**（@60fps）。

### 5.3 小屏速度缩放（`offline.ts` · `setSpeed`）

```js
setSpeed(newSpeed?) {
  const speed = newSpeed || this.currentSpeed;
  if (this.dimensions.width < DEFAULT_DIMENSIONS.width) {          // < 600
    const mobileSpeed = this.hasSlowdown ? speed :
        speed * this.dimensions.width / DEFAULT_DIMENSIONS.width * this.config.mobileSpeedCoefficient;
    this.currentSpeed = mobileSpeed > speed ? speed : mobileSpeed;  // 取 min
  } else if (newSpeed) {
    this.currentSpeed = newSpeed;
  }
}
```

- 若画布宽度 < 600 且未开 slow：`currentSpeed = min(speed, speed * width/600 * 1.2)`
  例：width=400 → `6*400/600*1.2 = 4.8` → `currentSpeed = 4.8`。
- `setSpeed()` 在 `init()`、`restart()` 中各调用一次。
- 注意：`setSpeed()` 只在初始化/重开时调用，**不会随窗口 resize 重算速度**（resize 时也不再调用）。

### 5.4 重开时的重置

```js
// offline.ts · restart
this.distanceRan = 0;
this.setSpeed(this.config.speed);    // 回到 6（或小屏缩放值）
this.time = getTimeStamp();
```

---

## 6. 距离与分数

### 6.1 `distanceRan` 每帧增量

```js
distanceRan += currentSpeed * deltaTime / msPerFrame;   // msPerFrame = 1000/FPS = 16.6667
```

等价写法：`distanceRan += currentSpeed * deltaTime * 0.06`。
正好 60fps（`deltaTime === 16.6667`）时：`distanceRan += currentSpeed`（即 6 px/帧 = 360 px/s）。

### 6.2 距离 → 显示分数

```js
// distance_meter.ts
getActualDistance(distance) {
  return distance ? Math.round(distance * Config.COEFFICIENT) : 0;   // COEFFICIENT = 0.025
}
// offline.ts · update → distanceMeter.update(deltaTime, Math.ceil(this.distanceRan))
```

完整链条：
```
score = Math.round( Math.ceil(distanceRan) * 0.025 )
```

- 初始速度下 ≈ `360 px/s * 0.025 = 9 分/秒`。
- 最高速度下 ≈ `780 px/s * 0.025 = 19.5 分/秒`。
- `distanceRan === 0` 时直接返回 `0`（不取 round）。

### 6.3 位数规则（`distance_meter.ts` · `init` / `update`）

```js
// init()
this.maxScoreUnits = Config.MAX_DISTANCE_UNITS;          // 5
this.maxScore = this.maxScoreUnits;                      // 5（临时）
for (let i = 0; i < this.maxScoreUnits; i++) {
  this.draw(i, 0);
  this.defaultString += '0';                             // '00000'
  maxDistanceStr += '9';                                 // '99999'
}
this.maxScore = parseInt(maxDistanceStr, 10);            // 99999

// update()
if (distance > this.maxScore && this.maxScoreUnits === Config.MAX_DISTANCE_UNITS) {
  this.maxScoreUnits++;                                  // → 6
  this.maxScore = parseInt(this.maxScore + '9', 10);     // 999999
}
const distanceStr = (this.defaultString + distance).substr(-this.maxScoreUnits);
this.digits = distanceStr.split('');
```

- 默认 5 位，前导补 `0`（显示 `00000`）。
- 只有当分数 **> 99999** 时才升到 6 位。

### 6.4 X 位置

```js
// distance_meter.ts · calcXpos
this.x = canvasWidth - (Dimensions.DEST_WIDTH * (this.maxScoreUnits + 1));   // canvasWidth - 11*6 = -66
// draw(): targetX = digitPos * DEST_WIDTH;  ctx.translate(highScore ? highScoreX : this.x, this.y)
// highScoreX = this.x - (this.maxScoreUnits * 2) * Dimensions.WIDTH          // this.x - 100
// y = 5
```

### 6.5 最高分

```js
// offline.ts · initializeHighScore
highScore = Math.ceil(highScore);
if (highScore < this.highestScore) { ...同步回 profile...; return; }
this.highestScore = highScore;
this.distanceMeter.setHighScore(this.highestScore);

// offline.ts · saveHighScore
this.highestScore = Math.ceil(distanceRan);
this.distanceMeter.setHighScore(this.highestScore);

// distance_meter.ts · setHighScore
distance = this.getActualDistance(distance);
this.highScore = 'HI ' + (this.defaultString + distance).substr(-this.maxScoreUnits);
```

- 显示字符串为 `"HI 00000"`，绘制时 `globalAlpha = 0.8`。
- 字符映射：数字 `0-9` → 精灵索引 `0-9`；`'H'` → `10`；`'I'` → `11`。
- 游戏结束时：`if (this.distanceRan > this.highestScore) this.saveHighScore(this.distanceRan)`。

---

## 7. 里程碑 / 成就闪烁

`distance_meter.ts` · `update`：

```js
if (!this.achievement) {
  distance = this.getActualDistance(distance);
  // ... 位数扩展 ...
  if (distance > 0) {
    if (distance % Config.ACHIEVEMENT_DISTANCE === 0) {   // ACHIEVEMENT_DISTANCE = 100
      this.achievement = true;
      this.flashTimer = 0;
      playSound = true;
    }
    const distanceStr = (this.defaultString + distance).substr(-this.maxScoreUnits);
    this.digits = distanceStr.split('');
  } else {
    this.digits = this.defaultString.split('');
  }
} else {
  if (this.flashIterations <= Config.FLASH_ITERATIONS) {   // <= 3
    this.flashTimer += deltaTime;
    if (this.flashTimer < Config.FLASH_DURATION) {          // < 250 ms
      paint = false;
    } else if (this.flashTimer > Config.FLASH_DURATION * 2) {  // > 500 ms
      this.flashTimer = 0;
      this.flashIterations++;
    }
  } else {
    this.achievement = false;
    this.flashIterations = 0;
    this.flashTimer = 0;
  }
}
if (paint) { for (i = digits.length-1; i>=0; i--) draw(i, parseInt(digits[i])); }
this.drawHighScore();
return playSound;
```

**精确行为：**

| 项 | 值 |
|---|---|
| 触发分数间隔 | 每 **100** 分（`distance % 100 === 0`，`distance` 是 `Math.round(distanceRan*0.025)`） |
| 单次隐藏时长 | `flashTimer < 250 ms` 期间不绘制数字 |
| 单次显示时长 | `250 ms ≤ flashTimer ≤ 500 ms` 期间绘制数字 |
| 一个闪烁周期 | **500 ms** |
| 闪烁次数 | `flashIterations` 从 0 计到 3，即 `flashIterations <= 3` 期间共 **4 个 250ms 隐藏窗 + 4 个 250ms 显示窗 ≈ 2000 ms**，然后 `flashIterations=4 > 3` → 复位 |
| 计分是否暂停 | **`distanceRan` 照常累加**；只是**显示**冻结（`this.digits` 在 `achievement===true` 期间不更新）。结束时数字会一次性跳到当前值 |
| 声音 | `update()` 返回 `playSound=true` 的那一帧播放 `RunnerSounds.SCORE`（若未启用 audio cues） |

---

## 8. 跳跃物理（逐条精确）

### 8.1 `startJump`（`trex.ts`）

```js
startJump(speed) {
  if (!this.jumping) {
    this.update(0, Status.JUMPING);                                  // status=JUMPING, frames=[0], msPerFrame=1000/60
    this.jumpVelocity = this.config.initialJumpVelocity - (speed / 10);  // -10 - speed/10
    this.jumping = true;
    this.reachedMinHeight = false;
    this.speedDrop = false;
    if (this.config.invertJump) {
      this.minJumpHeight = this.groundYPos + this.config.minJumpHeight;
    }
  }
}
```

**初速度公式（必须照抄）：**
```
jumpVelocity = -10 - (currentSpeed / 10)
```
- `currentSpeed = 6` → `-10.6`
- `currentSpeed = 13` → `-11.3`

同一帧内 `startJump` 前会调 `this.tRex.update(0, Status.JUMPING)`，把 `jumping` 之外的动画状态切到 JUMPING。

### 8.2 `updateJump`（`trex.ts`）

```js
updateJump(deltaTime) {
  const msPerFrame = animFrames[this.status].msPerFrame;   // 1000/60
  const framesElapsed = deltaTime / msPerFrame;            // = deltaTime * 0.06

  if (this.speedDrop) {
    this.yPos += Math.round(this.jumpVelocity * this.config.speedDropCoefficient * framesElapsed);
  } else if (this.config.invertJump) {
    this.yPos -= Math.round(this.jumpVelocity * framesElapsed);
  } else {
    this.yPos += Math.round(this.jumpVelocity * framesElapsed);
  }

  this.jumpVelocity += this.config.gravity * framesElapsed;

  // 最小高度
  if (this.config.invertJump && (this.yPos > this.minJumpHeight) ||
      !this.config.invertJump && (this.yPos < this.minJumpHeight) ||
      this.speedDrop) {
    this.reachedMinHeight = true;
  }

  // 最大高度
  if (this.config.invertJump && (this.yPos > -this.config.maxJumpHeight) ||
      !this.config.invertJump && (this.yPos < this.config.maxJumpHeight) ||
      this.speedDrop) {
    this.endJump();
  }

  // 落地
  if ((this.config.invertJump && (this.yPos < this.groundYPos)) ||
      (!this.config.invertJump && (this.yPos > this.groundYPos))) {
    this.reset();
    this.jumpCount++;
    if (this.hasAudioCues) { ...loopFootSteps()... }
  }
}
```

**必须精确实现的两个点：**

1. **`Math.round` 只包住 `jumpVelocity * framesElapsed`**，不包 `jumpVelocity` 也不包累加结果：
   `yPos += Math.round(jumpVelocity * framesElapsed)`。
   （`Math.round` 对负数的行为：`Math.round(-10.6) = -11`，`Math.round(-8.8) = -9`，`Math.round(-0.5) = -0`。JS 语义必须一致，PowerShell 的 `[Math]::Round` 默认是**银行家舍入**，必须改用 `[Math]::Floor(x + 0.5)` 才能等价！）
2. **`jumpVelocity` 的更新在位置更新之后**，且是 `+=` 而不是先算再赋值。

**判定条件的绝对值陷阱（务必照抄）：**

- `minJumpHeight` 字段是**绝对值**：`groundYPos - config.minJumpHeight = 93 - 30 = 63`。
- `maxJumpHeight` 判定用的是 **裸配置值 `30`**，与 `groundYPos` 无关：
  `!invertJump && (this.yPos < this.config.maxJumpHeight)` → `yPos < 30`。

### 8.3 `endJump`（松键触发）

```js
endJump() {
  if (this.reachedMinHeight && this.jumpVelocity < this.config.dropVelocity) {
    this.jumpVelocity = this.config.dropVelocity;      // dropVelocity = -5
  }
}
```

- 若尚未达到最小高度（`reachedMinHeight === false`），**什么都不做**（早期松键不影响跳跃）。
- 若已达最小高度且当前上升速度比 `-5` 更快（`< -5`），则**钳制到 `-5`**（上升变慢 → 峰值变低）。

### 8.4 `setSpeedDrop`（下箭头按下 / 空中）

```js
setSpeedDrop() {
  this.speedDrop = true;
  this.jumpVelocity = 1;          // 注意：直接赋正值 1
}
```

配合 §8.2：`yPos += Math.round(1 * 3 * framesElapsed)` → 第一帧 +3px，之后 `jumpVelocity += 0.6*framesElapsed`，即 1→1.6→2.2→…，每像素位移 ×3。

### 8.5 `reset`（`trex.ts`）

```js
reset() {
  this.xPos = this.xInitialPos;        // = startXPos = 50（intro 后）
  this.yPos = this.groundYPos;         // 93
  this.jumpVelocity = 0;
  this.jumping = false;
  this.ducking = false;
  this.update(0, Status.RUNNING);
  this.speedDrop = false;
  this.jumpCount = 0;
}
```

落地时 `updateJump` 内是 `this.reset(); this.jumpCount++;` → 落地后 `jumpCount === 1`。
`offline.ts · update` 用 `if (this.tRex.jumpCount === 1 && !this.playingIntro) this.playIntro();` 触发开场动画。

> 注意 `reset()` 会把 `speedDrop` 置 `false`；`trex.ts · update` 里
> `if (this.speedDrop && this.yPos === this.groundYPos) { this.speedDrop = false; this.setDuck(true); }`
> 只在 `updateJump` 未走"严格越界"分支（`yPos` 恰好 `=== 93`）时才可能命中。

### 8.6 长按 vs 短按（精确语义）

| 操作 | 事件 | 后果 |
|---|---|---|
| 按下 jump 键（38/32）或 touchstart / 鼠标 pointerdown | `onKeyDown` | `tRex.startJump(currentSpeed)`，初速度 `-10 - speed/10`；**按住期间没有任何额外加速** |
| 松开 jump 键 / touchend / pointerup | `onKeyUp` → `tRex.endJump()` | 若 `reachedMinHeight` 且 `jumpVelocity < -5` → `jumpVelocity = -5`（上升减速，峰值降低） |
| 一直按住不松 | 无 `endJump` | 唯一的高度限制是 `updateJump` 内每帧调用的 `endJump()`（`yPos < 30` 时）。按住可达到完整高度 |
| 空中按 ↓（40） | `onKeyDown` → `tRex.setSpeedDrop()` | `speedDrop = true; jumpVelocity = 1;` 立刻以 3× 速度下落 |
| 松开 ↓ | `onKeyUp` | `tRex.speedDrop = false; tRex.setDuck(false);` |

**量化示例（`currentSpeed = 6`，60fps，`framesElapsed = 1.0`，长按不松）：**

```
yPos 起点 93，jumpVelocity 起点 -10.6
f1 : yPos += round(-10.6) = -11 → 82 ;  jv = -10.0
f2 : → 72 ; jv = -9.4
f3 : → 63 ; jv = -8.8
f4 : → 54 ; jv = -8.2   (54 < 63 → reachedMinHeight = true)
f5 : → 46 ; jv = -7.6
f6 : → 38 ; jv = -7.0
f7 : → 31 ; jv = -6.4
f8 : → 25 ; jv = -5.8   (25 < 30 → endJump → jv = -5)
f9 : → 20 ; jv = -4.4
f12: →  9 ; jv = -2.6
f16: →  2 ; jv = -0.2   ← 峰值 yPos ≈ 2（跳跃高度 ≈ 91 px）
f17: →  2 ; jv =  0.4
f19: →  3 ; jv =  1.6
f35: →101 (>93) → reset(); jumpCount++   ← 滞空 ≈ 35 帧 ≈ 583 ms
```

---

## 9. 下蹲（duck）

### 9.1 触发（`offline.ts` · `onKeyDown`）

```js
} else if (this.playing && e instanceof KeyboardEvent &&
           runnerKeycodes.duck.includes(e.keyCode)) {      // 40
  e.preventDefault();
  if (this.tRex.jumping) {
    this.tRex.setSpeedDrop();            // 空中按 ↓ → 速降
  } else if (!this.tRex.jumping && !this.tRex.ducking) {
    this.tRex.setDuck(true);             // 地面按 ↓ → 下蹲
  }
}
```

### 9.2 状态切换（`trex.ts` · `setDuck`）

```js
setDuck(isDucking) {
  if (isDucking && this.status !== Status.DUCKING) {
    this.update(0, Status.DUCKING);       // frames [264, 323], msPerFrame 1000/8 = 125ms
    this.ducking = true;
  } else if (this.status === Status.DUCKING) {
    this.update(0, Status.RUNNING);       // frames [88, 132], msPerFrame 1000/12
    this.ducking = false;
  }
}
```

### 9.3 空中 speedDrop ↔ 下蹲互转

```js
// trex.ts · update （每帧末尾）
if (this.speedDrop && this.yPos === this.groundYPos) {
  this.speedDrop = false;
  this.setDuck(true);
}
```

即：**速降落地那一帧，如果 `speedDrop` 仍为 true 且 `yPos` 恰好等于 `groundYPos`，自动转为下蹲。**
（若 `updateJump` 的落地判定 `yPos > groundYPos` 先触发 `reset()`，`speedDrop` 会被清 `false`，此时靠按键重复的 `keydown` 走 `setDuck(true)` 分支。）

### 9.4 下蹲时的尺寸与碰撞盒

| 项 | 值 |
|---|---|
| `widthDuck`（输出宽） | `59` |
| `heightDuck` | `25`（**仅作配置存在，`draw()` 未使用**） |
| `yPos` | **不变**，仍是 `groundYPos = 93` |
| 绘制裁剪 | `sourceWidth = widthDuck = 59`，`sourceHeight = config.height = 47`；`drawImage(img, sourceX, sourceY, 59, 47, xPos, 93, 59, 47)` |
| `sourceX` | `spritePos.x + 264`（帧 0）或 `+ 323`（帧 1），ldpi |
| 碰撞盒 | `[ new CollisionBox(1, 18, 55, 25) ]` |

> **注意**：`draw()` 里 `sourceHeight` 始终取 `config.height`（47），**不是** `heightDuck`（25）。
> 因此下蹲帧是从精灵表里裁 **59×47** 的块。若你的精灵表里下蹲图只有 25 px 高，必须把它**底部对齐**放在这 47 px 的裁剪窗内，否则碰撞盒（相对 `yPos+1` 偏移 18、高 25）会与可见图形错位。

---

## 10. 碰撞检测

`offline.ts` · `checkForCollision` / `boxCompare` / `createAdjustedCollisionBox`，`obstacle.ts` · `collisionBoxes` / `cloneCollisionBoxes`。

### 10.1 算法：两层 AABB，全部无容差

```js
checkForCollision(obstacle, tRex, canvasCtx?) {
  // 外层包围盒：+1 / -2 是因为精灵四周有 1px 白边
  const tRexBox = new CollisionBox(
      tRex.xPos + 1, tRex.yPos + 1, tRex.config.width - 2, tRex.config.height - 2);

  const obstacleBox = new CollisionBox(
      obstacle.xPos + 1, obstacle.yPos + 1,
      obstacle.typeConfig.width * obstacle.size - 2,
      obstacle.typeConfig.height - 2);

  if (boxCompare(tRexBox, obstacleBox)) {          // 第一层：粗筛
    const collisionBoxes = obstacle.collisionBoxes;
    let tRexCollisionBoxes = this.isAltGameModeEnabled()
        ? runnerSpriteDefinition.tRex.collisionBoxes
        : tRex.getCollisionBoxes();                // ducking ? ducking : running
    for (const tRexCollisionBox of tRexCollisionBoxes) {
      for (const obstacleCollixionBox of collisionBoxes) {   // 第二层：子盒两两相交
        const adjTrexBox = createAdjustedCollisionBox(tRexCollisionBox, tRexBox);
        const adjObstacleBox = createAdjustedCollisionBox(obstacleCollixionBox, obstacleBox);
        if (boxCompare(adjTrexBox, adjObstacleBox)) return [adjTrexBox, adjObstacleBox];
      }
    }
  }
  return null;
}
```

```js
createAdjustedCollisionBox(box, adjustment) {
  return new CollisionBox(box.x + adjustment.x, box.y + adjustment.y, box.width, box.height);
}

boxCompare(tRexBox, obstacleBox) {
  const tRexBoxX = tRexBox.x, tRexBoxY = tRexBox.y;
  const obstacleBoxX = obstacleBox.x, obstacleBoxY = obstacleBox.y;
  if (tRexBoxX < obstacleBoxX + obstacleBox.width &&
      tRexBoxX + tRexBox.width > obstacleBoxX &&
      tRexBoxY < obstacleBoxY + obstacleBox.height &&
      tRexBox.height + tRexBoxY > obstacleBoxY) {
    return true;
  }
  return false;
}
```

**关键点：**
- 子盒的绝对坐标 = `子盒.x + 外层盒.x`、`子盒.y + 外层盒.y`（`外层盒` 已经含 `+1`）。
  即 `absX = box.x + xPos + 1`，`absY = box.y + yPos + 1`。
- 判定用严格不等号（`<` / `>`），**无任何容差 / padding**，除 `+1 / -2` 的白边修正外。
- **只检测 `this.horizon.obstacles[0]`**（每帧只测数组里第一个障碍）。
- 碰撞盒对象是**每个障碍实例克隆的**（`cloneCollisionBoxes`），因为 size 会改写碰撞盒。

### 10.2 经典「速通」子盒（把 6 个椭圆近似成 6 个矩形）

起跳前，T-Rex 的绝对碰撞盒（`xPos = 50`，`yPos = 93`）：

| 子盒定义 | 绝对 X 区间 | 绝对 Y 区间 |
|---|---|---|
| `(22, 0, 17, 16)` | 73 – 90 | 94 – 110 |
| `(1, 18, 30, 9)` | 52 – 82 | 112 – 121 |
| `(10, 35, 14, 8)` | 61 – 75 | 129 – 137 |
| `(1, 24, 29, 5)` | 52 – 81 | 118 – 123 |
| `(5, 30, 21, 4)` | 56 – 77 | 124 – 128 |
| `(9, 34, 15, 4)` | 60 – 75 | 128 – 132 |

下蹲时绝对盒（`xPos = 50`，`yPos = 93`）：`(1,18,55,25)` → `X 52 – 107`，`Y 112 – 137`。

> **⚠ 已知几何陷阱（会影响手感，务必照抄）**：外层 `tRexBox` 用的是 `tRex.config.width - 2 = 42`，**即使下蹲也还是 42**（用的是 `config.width`，不是 `widthDuck`）。
> 外层盒 X 区间 = `51 – 93`。
> 而子盒 `(1,18,55,25)` 的 X 区间是 `52 – 107`，**比外层盒宽出 14 px**。
> 因为必须先过外层盒粗筛，**下蹲时真正生效的横向命中区被裁到 52 – 93（约 41 px 宽）**，而不是 55 px。

### 10.3 障碍碰撞盒的 size 改写（`obstacle.ts` · `init`）

```js
if (this.size > 1) {
  this.collisionBoxes[1].width = this.width - this.collisionBoxes[0].width - this.collisionBoxes[2].width;
  this.collisionBoxes[2].x = this.width - this.collisionBoxes[2].width;
}
```

展开成实际值：

| 类型 | size | `width` | 盒0 | 盒1 | 盒2 |
|---|---|---|---|---|---|
| cactusSmall | 1 | 17 | `(0,7,5,27)` | `(4,0,6,34)` | `(10,4,7,14)` |
| cactusSmall | 2 | 34 | `(0,7,5,27)` | `(4,0,22,34)` | `(27,4,7,14)` |
| cactusSmall | 3 | 51 | `(0,7,5,27)` | `(4,0,39,34)` | `(44,4,7,14)` |
| cactusLarge | 1 | 25 | `(0,12,7,38)` | `(8,0,7,49)` | `(13,10,10,38)` |
| cactusLarge | 2 | 50 | `(0,12,7,38)` | `(8,0,33,49)` | `(40,10,10,38)` |
| cactusLarge | 3 | 75 | `(0,12,7,38)` | `(8,0,58,49)` | `(65,10,10,38)` |
| pterodactyl | 1 | 46 | 5 个盒不变（`multipleSpeed = 999` 永远把 size 压回 1） | | |

---

## 11. 障碍物系统（重点）

### 11.1 种类与尺寸总表

见 §2.15。补充要点：

- 仙人掌只有 **2 种底座**（small / large），靠 `size ∈ {1,2,3}` 拼成 1~3 连体。
- `size` 不是"从 1 到 3 枚举每种造型"，而是**同一个精灵横向拉伸/平铺**：源 X 计算见 §11.4。
- 翼龙只有 1 种，靠 `yPos` 三档表示飞行高度。

### 11.2 生成调度（`horizon.ts` · `updateObstacles`）

```js
private updateObstacles(deltaTime, currentSpeed) {
  const updatedObstacles = this.obstacles.slice(0);

  for (const obstacle of this.obstacles) {
    obstacle.update(deltaTime, currentSpeed);
    if (obstacle.remove) {
      updatedObstacles.shift();                 // ⚠ 从数组头部移除
    }
  }
  this.obstacles = updatedObstacles;

  if (this.obstacles.length > 0) {
    const lastObstacle = this.obstacles.at(-1);
    if (lastObstacle && !lastObstacle.followingObstacleCreated &&
        lastObstacle.isVisible() &&
        (lastObstacle.xPos + lastObstacle.width + lastObstacle.gap) < this.dimensions.width) {
      this.addNewObstacle(currentSpeed);
      lastObstacle.followingObstacleCreated = true;
    }
  } else {
    this.addNewObstacle(currentSpeed);          // 空数组 → 立刻生成第一个
  }
}
```

**精确结论：**

| 问题 | 答案 |
|---|---|
| 一帧生成几个？ | **最多 1 个**。`addNewObstacle` 每帧最多被调用一次；它内部只有**类型重选递归**，不会创建多个实例 |
| 生成条件 | 最后一个障碍满足 `lastObstacle.xPos + lastObstacle.width + lastObstacle.gap < canvasWidth`，且该障碍的 `followingObstacleCreated === false` |
| 首个障碍 | `obstacles` 为空时（开局 / `horizon.reset()` 后）立即生成，且 `updateObstacles` 只在 `hasObstacles`（即 `runningTime > 3000`）时才被调用 |
| 是否会按速度一次填满屏幕 | **不会**。严格一帧一个，靠 gap 条件节流 |
| 移除条件 | `Obstacle.isVisible() === (xPos + width > 0)`；为 false 时 `remove = true`，下一帧从数组移除 |

> **⚠ 数组移除的已知怪癖**：`updatedObstacles.shift()` 永远删**数组第一个**元素，而不是"刚刚被标记 remove 的那个"。
> 由于 `speedOffset = ±0.8`，翼龙可能相对仙人掌前后换位；一旦**非队首**的翼龙先越界，`shift()` 会错误地把**仍然可见的队首**剔除。
> 逐帧复刻时如果照抄这个 `shift()`，你会得到和 Chrome 完全一致的（偶发）行为；如果改成"按 remove 标记过滤"，行为会**与 Chrome 不同**。

### 11.3 类型选择与去重（`horizon.ts` · `addNewObstacle` / `duplicateObstacleCheck`）

```js
addNewObstacle(currentSpeed) {
  const obstacleCount =
      this.obstacleTypes[this.obstacleTypes.length - 1].type !== 'collectable' ||
          (this.resourceProvider.isAltGameModeEnabled() && !this.altGameModeActive ||
           this.altGameModeActive)
      ? this.obstacleTypes.length - 1
      : this.obstacleTypes.length - 2;

  const obstacleTypeIndex = obstacleCount > 0 ? getRandomNum(0, obstacleCount) : 0;
  const obstacleType = this.obstacleTypes[obstacleTypeIndex];

  if ((obstacleCount > 0 && this.duplicateObstacleCheck(obstacleType.type)) ||
      currentSpeed < obstacleType.minSpeed) {
    this.addNewObstacle(currentSpeed);                       // 递归重选
  } else {
    const obstacleSpritePos = this.spritePos[obstacleType.type];
    this.obstacles.push(new Obstacle(
        this.canvasCtx, obstacleType, obstacleSpritePos, this.dimensions,
        this.gapCoefficient, currentSpeed, obstacleType.width,
        this.resourceProvider, this.altGameModeActive));
    this.obstacleHistory.unshift(obstacleType.type);
    if (this.obstacleHistory.length > 1) {
      this.obstacleHistory.splice(this.resourceProvider.getConfig().maxObstacleDuplication);
    }
  }
}
```

**默认玩法（非 alt）逐项展开：**
- `obstacleTypes = spriteDefinitionByType.original.obstacles`（4 项，最后一项是 `collectable`）
- `isAltGameModeEnabled() === false` → 三元表达式整体为 `false`
- → `obstacleCount = 4 - 2 = 2`
- → `obstacleTypeIndex = getRandomNum(0, 2)` ∈ **{0, 1, 2}** → `cactusSmall` / `cactusLarge` / `pterodactyl`
  （`collectable` 在默认玩法下**永远不会生成**）

```js
duplicateObstacleCheck(nextObstacleType) {
  let duplicateCount = 0;
  for (const obstacle of this.obstacleHistory) {
    duplicateCount = obstacle === nextObstacleType ? duplicateCount + 1 : 0;
  }
  return duplicateCount >= this.resourceProvider.getConfig().maxObstacleDuplication;  // >= 2
}
```

- `obstacleHistory` 用 `unshift` 插到头部，并且 `splice(2)` **只保留最近 2 条**。
- 循环是"数前缀连续相同个数"，遇到不同就归零。
- 由于历史只有 2 条，`duplicateCount` 最大为 2。
- `maxObstacleDuplication = 2` 的语义：**不允许连续 3 个同类型**（`>= 2` 表示已经连续 2 个就打回重选）。

**`minSpeed` 过滤：**
- `cactusSmall` / `cactusLarge`：`minSpeed = 0` → 从第 0 帧就可能出现
- `pterodactyl`：`minSpeed = 8.5`

**翼龙何时开始出现（精确回答）：**
> 判据是**速度阈值**，不是分数阈值。`currentSpeed >= 8.5` 时翼龙才可能被选中。
> `currentSpeed` 从 6 起每帧 `+0.001` → 需 `2500` 帧（@60fps 约 **41.7 秒**）达到 8.5。
> 该时刻累计 `distanceRan ≈ 18124 px` → 显示分数约 **453 分**。
> （`multipleSpeed = 999` 与 `minGap = 150` 不参与"何时出现"的判定。）

### 11.4 障碍构造与源 X（`obstacle.ts` · `constructor` / `init` / `draw`）

```js
// constructor
this.gapCoefficient = this.resourceProvider.hasSlowdown ? gapCoefficient * 2 : gapCoefficient;
this.size  = getRandomNum(1, maxObstacleLength);        // maxObstacleLength = 3 → {1,2,3} 均匀
this.xPos  = dimensions.width + xOffset;                // xOffset = obstacleType.width
this.yPos  = 0;
this.width = 0;
this.collisionBoxes = [];
this.gap = 0;
this.speedOffset = 0;
this.currentFrame = 0;
this.timer = 0;
this.init(speed);
```

```js
// init(speed)
this.cloneCollisionBoxes();
if (this.size > 1 && this.typeConfig.multipleSpeed > speed) { this.size = 1; }
this.width = this.typeConfig.width * this.size;

if (Array.isArray(this.typeConfig.yPos)) {                       // 翼龙
  const yPosConfig = IS_MOBILE ? this.typeConfig.yPosMobile : this.typeConfig.yPos;
  this.yPos = yPosConfig[getRandomNum(0, yPosConfig.length - 1)];
} else {
  this.yPos = this.typeConfig.yPos;
}

this.draw();
if (this.size > 1) { /* §10.3 改写碰撞盒 */ }

if (this.typeConfig.speedOffset) {
  this.speedOffset = Math.random() > 0.5 ? this.typeConfig.speedOffset : -this.typeConfig.speedOffset;
}

this.gap = this.getGap(this.gapCoefficient, speed);
if (this.resourceProvider.hasAudioCues) { this.gap *= 2; }
```

**初始 X 位置（精确）：**
```
obstacle.xPos = canvasWidth + obstacleType.width
```
（`xOffset` 参数传的是 `obstacleType.width`，**不是** `obstacleType.width * size`。）
- cactusSmall：`xPos = 600 + 17 = 617`
- cactusLarge：`xPos = 600 + 25 = 625`
- pterodactyl：`xPos = 600 + 46 = 646`

**多连体允许速度：**
- `size > 1` 且 `multipleSpeed > speed` → 强制 `size = 1`。
- `cactusSmall` 需要 `speed >= 4`（初始 6 就满足 → 开局即可出现 2/3 连体）。
- `cactusLarge` 需要 `speed >= 7`（约 1000 帧 ≈ 16.7 秒后才可能出现 2/3 连体）。
- `pterodactyl`：`multipleSpeed = 999` → `size` 永远是 1。

**移动与动画：**

```js
// obstacle.ts · update
if (!this.remove) {
  if (this.typeConfig.speedOffset) { speed += this.speedOffset; }
  this.xPos -= Math.floor((speed * FPS / 1000) * deltaTime);      // = Math.floor(speed * 0.06 * deltaTime)
  if (this.typeConfig.numFrames) {                                 // 翼龙扇翅
    this.timer += deltaTime;
    if (this.timer >= this.typeConfig.frameRate) {                 // frameRate = 1000/6 ≈ 166.67 ms
      this.currentFrame = this.currentFrame === this.typeConfig.numFrames - 1 ? 0 : this.currentFrame + 1;
      this.timer = 0;
    }
  }
  this.draw();
  if (!this.isVisible()) { this.remove = true; }
}
```

**翼龙速度偏移：**
```
speed_effective = currentSpeed + speedOffset,  speedOffset ∈ {+0.8, -0.8}（构造时 50/50 随机）
位移 = floor(speed_effective * FPS/1000 * deltaTime)
```
即翼龙比世界**快或慢 0.8 px/帧@60fps**（±48 px/s）。

**翼龙翅膀帧率：** `1000/6 ms` ≈ **6 fps**（`frameRate: 1000 / 6`，`numFrames: 2`）。

**绘制（源 X）：**

```js
let sourceWidth = this.typeConfig.width;    // HIDPI 时 *2
let sourceHeight = this.typeConfig.height;  // HIDPI 时 *2
let sourceX = (sourceWidth * this.size) * (0.5 * (this.size - 1)) + this.spritePos.x;
if (this.currentFrame > 0) { sourceX += sourceWidth * this.currentFrame; }
ctx.drawImage(this.imageSprite, sourceX, this.spritePos.y,
              sourceWidth * this.size, sourceHeight,
              this.xPos, this.yPos,
              this.typeConfig.width * this.size, this.typeConfig.height);
```

源 X 偏移系数 `(size) * (0.5*(size-1))` = `{1→0, 2→1, 3→3}` 倍的 `typeConfig.width`：

| 类型 | size 1 | size 2 | size 3 | 帧 2（翼龙） |
|---|---|---|---|---|
| cactusSmall (ldpi, base 228, w 17) | 228 | 245 | 279 | — |
| cactusLarge (ldpi, base 332, w 25) | 332 | 357 | 407 | — |
| pterodactyl (ldpi, base 134, w 46) | 134 | — | — | 180 |

### 11.5 生成间隔 gap 的**完整算法**（`obstacle.ts` · `getGap`）

```js
getGap(gapCoefficient, speed) {
  const minGap = Math.round(this.width * speed + this.typeConfig.minGap * gapCoefficient);
  const maxGap = Math.round(minGap * maxGapCoefficient);     // maxGapCoefficient = 1.5
  return getRandomNum(minGap, maxGap);
}
```

**最终公式（默认玩法）：**
```
minGap = Math.round( (typeConfig.width * size) * speed_at_creation + typeConfig.minGap * 0.6 )
maxGap = Math.round( minGap * 1.5 )
gap    = Math.floor(Math.random() * (maxGap - minGap + 1)) + minGap     // 闭区间 [minGap, maxGap]
```

**依赖关系澄清（用户专门问到的）：**

| 输入 | 是否参与 gap 公式 | 说明 |
|---|---|---|
| 障碍宽度 `typeConfig.width * size` | ✅ | 见上式 |
| `currentSpeed`（生成瞬间的值） | ✅ | 见上式 |
| `gapCoefficient` | ✅ | 默认 `0.6`；slow 模式 `0.3` 再 `*2` = `0.6`（`Obstacle` 构造里的 `hasSlowdown ? *2`） |
| `typeConfig.minGap` | ✅ | small/large = 120，pterodactyl = 150，collectable = 9999 |
| **画布宽度 / 屏幕尺寸** | ❌ **完全不出现** | 画布宽度只出现在"何时生成下一个"的**门限条件**里（§11.2），不在 gap 数值里 |
| `maxGapCoefficient`（=1.5） | ✅ | 只用于 `maxGap` |

**具体算例（`gapCoefficient = 0.6`）：**

| 障碍 | speed | minGap | maxGap | gap 取值区间 |
|---|---|---|---|---|
| cactusSmall size 1 | 6 | `round(102 + 72) = 174` | `round(261) = 261` | 174 – 261 |
| cactusSmall size 2 | 6 | `round(204 + 72) = 276` | `round(414) = 414` | 276 – 414 |
| cactusSmall size 3 | 6 | `round(306 + 72) = 378` | `round(567) = 567` | 378 – 567 |
| cactusLarge size 1 | 6 | `round(150 + 72) = 222` | `round(333) = 333` | 222 – 333 |
| cactusLarge size 3 | 13 | `round(975 + 72) = 1047` | `round(1570.5) = 1571` | 1047 – 1571 |
| pterodactyl size 1 | 8.5 | `round(391 + 90) = 481` | `round(721.5) = 722` | 481 – 722 |

**随机取整细节（`utils.ts` · `getRandomNum`）：**
```js
export function getRandomNum(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}
```
- **闭区间** `[min, max]`，两端等概率（`Math.random()` ∈ [0,1)）。
- 没有任何 `+0.5` 或 `Math.round`；下界是 `Math.floor`，所以 min、max 都可取到。

### 11.6 `maxObstacleLength` 的参与方式

`maxObstacleLength` **只用于** `Obstacle` 构造时的 `this.size = getRandomNum(1, maxObstacleLength)`。
默认 `3`（来自 `obstacle.ts` 模块级 `let maxObstacleLength = 3`；`Runner.config.maxObstacleLength = 3` 这个字段**在默认玩法下并没有被用来设置它**——只有 `horizon.enableAltGameMode()` 会调 `setMaxObstacleLength(...)`）。

### 11.7 `maxObstacleDuplication` 的参与方式

见 §11.3。默认 `2`，来自 `Runner.config.maxObstacleDuplication`，**每帧通过 `resourceProvider.getConfig()` 实时读取**（不是构造时快照）。

### 11.8 障碍的移除

```js
isVisible() { return this.xPos + this.width > 0; }
```
`update()` 末尾：不可见 → `remove = true`；下一帧 `updateObstacles` 中从数组剔除（见 §11.2 的 `shift()` 怪癖）。

### 11.9 `collectable`（alt game mode 专用，默认玩法不出现）

- 只有 `spriteDefinitionByType.original.obstacles` 的最后一项；默认玩法 `obstacleCount = 2` 把它排除。
- 若被生成且被撞：`offline.ts · update` 中
  ```js
  if (this.isAltGameModeEnabled() && collision && firstObstacle &&
      firstObstacle.typeConfig.type === 'collectable') {
    this.horizon.removeFirstObstacle();
    this.tRex.setFlashing(true);
    collision = false;
    this.altGameModeFlashTimer = this.config.flashDuration;    // 1000
    this.runningTime = 0;
  }
  ```
  即"吃到"而非"撞死"。
- 构造时使用 `getAltCommonImageSprite()`，精灵坐标为 `{0,0}`。

### 11.10 `adjustObstacleSpeed()`（仅 slow / alt 模式）

```js
// horizon.ts
adjustObstacleSpeed() {
  for (let i = 0; i < this.obstacleTypes.length; i++) {
    if (this.resourceProvider.hasSlowdown) {
      this.obstacleTypes[i].multipleSpeed = this.obstacleTypes[i].multipleSpeed / 2;
      this.obstacleTypes[i].minGap *= 1.5;
      this.obstacleTypes[i].minSpeed = this.obstacleTypes[i].minSpeed / 2;
      const obstacleYpos = this.obstacleTypes[i].yPos;
      if (Array.isArray(obstacleYpos) && obstacleYpos.length > 1) {
        this.obstacleTypes[i].yPos = obstacleYpos[0];       // 翼龙固定为 100
      }
    }
  }
}
```
> ⚠ 该函数**直接改写 `spriteDefinitionByType.original.obstacles` 里的对象**（全局单例），所以来回切换 slow 会**累乘**（`minGap` 反复 `*1.5`）。逐帧复刻若不做 slow 模式，可忽略。

---

## 12. 云 / 地平线 / 背景元素

### 12.1 云（`horizon.ts` · `updateClouds`，`cloud.ts`）

```js
private updateClouds(deltaTime, speed) {
  const elSpeed = this.cloudSpeed / 1000 * deltaTime * speed;      // cloudSpeed = BG_CLOUD_SPEED = 0.2
  this.updateBackgroundEl(elSpeed, this.clouds, this.config.MAX_CLOUDS,
                          this.addCloud.bind(this), this.cloudFrequency);
  this.clouds = this.clouds.filter(obj => !obj.remove);
}

private updateBackgroundEl(elSpeed, bgElArray, maxBgEl, bgElAddFunction, frequency) {
  const numElements = bgElArray.length;
  if (!numElements) { bgElAddFunction(); return; }
  for (let i = numElements - 1; i >= 0; i--) { bgElArray[i].update(elSpeed); }
  const lastEl = bgElArray.at(-1);
  if (numElements < maxBgEl &&
      (this.dimensions.width - lastEl.xPos) > lastEl.gap &&
      frequency > Math.random()) {
    bgElAddFunction();
  }
}
```

```js
// cloud.ts
constructor: xPos = containerWidth;  gap = getRandomNum(100, 400);
init():      yPos = getRandomNum(Config.MAX_SKY_LEVEL, Config.MIN_SKY_LEVEL);   // getRandomNum(30, 71)
update(speed): xPos -= Math.ceil(speed);
isVisible(): xPos + 46 > 0
```

**精确要点：**
- 云的水平速度：`0.2/1000 * deltaTime * currentSpeed` px/帧，再 `Math.ceil()` 取整。
  @60fps,speed=6：`0.2/1000*16.667*6 = 0.02` → `Math.ceil(0.02) = 1` px/帧。
- 云的 Y 区间：`getRandomNum(30, 71)` → **30 到 71**（注意参数顺序是 `(MAX_SKY_LEVEL, MIN_SKY_LEVEL)`，数值上 min=30、max=71）。
- 最多 6 朵；新增还要求 `frequency(0.5) > Math.random()` 且离最后一朵的水平距离 > 该朵的 `gap`（100–400）。
- 构造函数里**一开始就 `addCloud()` 一次**（`Horizon` constructor）。
- 云的源尺寸 `46×14`，精灵坐标 ldpi `{x:86, y:2}`。
- 云的更新**没有** `deltaTime` 乘子（`elSpeed` 里已经乘过）。
- 云在 `Horizon.update` 中与 `nightMode.update()` 一起被调用，条件是 `!altGameModeActive || hasClouds`。

### 12.2 地平线（`horizon_line.ts`）

```js
constructor: xPos = [0, dimensions.width];  yPos = lineConfig.yPos;   // 127
             sourceXPos = [spritePos.x, spritePos.x + dimensions.width];  // [2, 602] ldpi
             dimensions = {width: 600, height: 12}

updatexPos(pos, increment) {
  const line1 = pos, line2 = pos === 0 ? 1 : 0;
  this.xPos[line1] -= increment;
  this.xPos[line2] = this.xPos[line1] + this.dimensions.width;
  if (this.xPos[line1] <= -this.dimensions.width) {
    this.xPos[line1] += this.dimensions.width * 2;
    this.xPos[line2] = this.xPos[line1] - this.dimensions.width;
    this.sourceXPos[line1] = this.getRandomType() + this.spritePos.x;    // 0 或 600
  }
}

update(deltaTime, speed) {
  const increment = Math.floor(speed * (FPS / 1000) * deltaTime);        // = floor(speed * 0.06 * deltaTime)
  this.updatexPos(this.xPos[0] <= 0 ? 0 : 1, increment);
  this.draw();
}

getRandomType() { return Math.random() > this.bumpThreshold ? this.dimensions.width : 0; }  // bumpThreshold = 0.5
reset() { this.xPos[0] = 0; this.xPos[1] = this.dimensions.width; }
```

- 平坦 / 起伏两套地面图，源 X 偏移 `0`（平坦）或 `600`（起伏），各 600×12，`yPos = 127`。
- `horizonConfig.BUMPY_THRESHOLD = 0.3` **未被使用**；实际阈值写死在 `HorizonLine.bumpThreshold = 0.5`。

### 12.3 `backgroundEl`

默认玩法下 `BackgroundEl` 只在 `altGameModeActive` 时才更新（`Horizon.update` 里 `if (this.altGameModeActive) this.updateBackgroundEls(deltaTime)`），且模块级 `globalConfig` 初值全 0。
`original.backgroundElConfig = {maxBgEls:1, maxGap:400, minGap:100, pos:0, speed:0.5, yPos:125}` 只有在 `enableAltGameMode()` 里 `setGlobalConfig(...)` 之后才生效。
**默认玩法可以完全不实现 `BackgroundEl`。**

---

## 13. 夜晚模式

### 13.1 触发（`offline.ts` · `update`，`isAltGameModeEnabled() === false` 分支）

```js
if (this.invertTimer > this.config.invertFadeDuration) {       // 12000
  this.invertTimer = 0;
  this.invertTrigger = false;
  this.invert(false);                                          // 移除 'inverted' class
} else if (this.invertTimer) {
  this.invertTimer += deltaTime;
} else {
  const actualDistance = this.distanceMeter.getActualDistance(Math.ceil(this.distanceRan));
  if (actualDistance > 0) {
    this.invertTrigger = !(actualDistance % this.config.invertDistance);   // invertDistance = 700
    if (this.invertTrigger && this.invertTimer === 0) {
      this.invertTimer += deltaTime;
      this.invert(false);
    }
  }
}
```

```js
private invert(reset) {
  const htmlEl = document.firstElementChild;
  if (reset) {
    htmlEl.classList.toggle('inverted', false);
    this.invertTimer = 0;
    this.inverted = false;
  } else {
    this.inverted = htmlEl.classList.toggle('inverted', this.invertTrigger);
  }
}
```

**精确结论：**

| 问题 | 答案 |
|---|---|
| 触发距离 | **显示分数**（`Math.round(distanceRan*0.025)`）为 **700 的正整数倍** 时（即 700、1400、2100、… 分）。slow 模式为 **350** |
| 首次触发时间 | 约 3592 帧 ≈ **60 秒**（此时速度 ≈ 9.59） |
| 渐变时长 | `invertFadeDuration = 12000 ms`。注意这是**保持**时长：`invertTimer` 从触发开始每帧 `+= deltaTime`，超过 12000 后复位并移除 `inverted` |
| 对游戏性的影响 | **纯视觉，不影响物理**。`inverted` 只是 HTML 根元素的 CSS class；所有物理量（速度、gap、跳跃、碰撞）都不读它 |
| 月亮/星星 | `Horizon.update` 中 `showNightMode = (this.isDarkMode !== this.inverted)`，传给 `nightMode.update(showNightMode)` |

### 13.2 月亮与星星（`night_mode.ts`）

```js
update(activated) {
  if (activated && this.opacity === 0) {
    this.currentPhase++;
    if (this.currentPhase >= PHASES.length) { this.currentPhase = 0; }
  }
  if (activated && (this.opacity < 1 || this.opacity === 0)) {
    this.opacity += Config.FADE_SPEED;                       // 0.035 / 帧
  } else if (this.opacity > 0) {
    this.opacity -= Config.FADE_SPEED;
  }

  if (this.opacity > 0) {
    this.xPos = this.updateXpos(this.xPos, Config.MOON_SPEED);   // 0.25
    if (this.drawStars) {
      for (let i = 0; i < Config.NUM_STARS; i++) {
        const star = this.stars[i];
        star.x = this.updateXpos(star.x, Config.STAR_SPEED);      // 0.3
      }
    }
    this.draw();
  } else {
    this.opacity = 0;
    this.placeStars();
  }
  this.drawStars = true;
}

updateXpos(currentPos, speed) {
  if (currentPos < -Config.WIDTH) { currentPos = this.containerWidth; }
  else { currentPos -= speed; }
  return currentPos;
}

private placeStars() {
  const segmentSize = Math.round(this.containerWidth / Config.NUM_STARS);   // /2
  for (let i = 0; i < Config.NUM_STARS; i++) {
    this.stars[i] = {
      x: getRandomNum(segmentSize * i, segmentSize * (i + 1)),
      y: getRandomNum(0, Config.STAR_MAX_Y),                                 // 0..70
      sourceY: IS_HIDPI ? (ldpi/hdpi star.y + 9*2*i) : (star.y + 9*i),
    };
  }
}

reset() { this.currentPhase = 0; this.opacity = 0; this.update(false); }
```

- 透明度步进 **0.035 / 帧**（@60fps 约 **1.7 秒** 淡入/淡出）。
- 月亮 `xPos` 每次 `-0.25`，小于 `-WIDTH(-20)` 时回卷到 `containerWidth`。
- 星星 2 颗，`x` 每次 `-0.3`，`y ∈ [0,70]`，尺寸 9×9。
- 月相 7 档，源 X 偏移 `[140,120,100,60,40,20,0]`；`currentPhase === 3` 时源宽 `WIDTH*2 = 40`。
- 月亮/星星的精灵来自 `getOrigImageSprite()`，源坐标 ldpi `moon {484,2}`、`star {645,2}`；`draw` 时 `Math.round(xPos)`。

---

## 14. 状态机与重开

### 14.1 `Trex.Status`（`trex.ts`）

```ts
export enum Status { CRASHED, DUCKING, JUMPING, RUNNING, WAITING }
```
即 `CRASHED=0, DUCKING=1, JUMPING=2, RUNNING=3, WAITING=4`。

### 14.2 Runner 侧的状态位

| 位 | 初始 | 含义 |
|---|---|---|
| `activated` | `false` | 是否已激活（第一次跳跃后 `true`） |
| `playing` | `false` | 主循环是否推进世界 |
| `playingIntro` | `false` | 开场动画（容器宽度 0.4s 展开）中 |
| `crashed` | `false` | 已撞 |
| `paused` | `false` | 已暂停（`stop()` 置 true） |
| `inverted` | `false` | 夜晚模式中 |
| `updatePending` | `false` | rAF 去重 |
| `jumpCount` | `0` | 每落地一次 = 1 |

### 14.3 状态转换表

| 从 | 事件 / 条件 | 到 | 代码位置 |
|---|---|---|---|
| 初始 | `constructor` → `tRex.update(0, WAITING)` | Trex=WAITING；Runner 未激活 | `trex.ts` · `constructor` |
| 未激活 | 空闲循环：`playing \|\| (!activated && tRex.blinkCount < maxBlinkCount)` | 每帧 `tRex.update`，眨眼 3 次后循环停止 | `offline.ts` · `update` 尾段 |
| 未激活 | 按 jump 键 / touchstart / 移动端鼠标 pointerdown | `loadSounds()` → `setPlayStatus(true)` → `update()` → `tRex.startJump()` | `offline.ts` · `onKeyDown` |
| Trex=RUNNING/WAITING | `startJump()` | Trex=JUMPING，`jumping=true` | `trex.ts` · `startJump` |
| Trex=JUMPING | 落地（`yPos > groundYPos`） | `reset()` + `jumpCount++` → Trex=RUNNING | `trex.ts` · `updateJump` |
| `jumpCount === 1 && !playingIntro` | 首帧检查 | `playIntro()`：`playingIntro=true`，CSS `intro .4s ease-out 1 both` | `offline.ts` · `playIntro` |
| CSS `webkitAnimationEnd` | `startGame()` | `playingIntro=false`，`runningTime=0`，`playCount++` | `offline.ts` · `startGame` |
| 地面 + ↓ | `setDuck(true)` | Trex=DUCKING，`ducking=true` | `trex.ts` · `setDuck` |
| 空中 + ↓ | `setSpeedDrop()` | `speedDrop=true; jumpVelocity=1` | `trex.ts` · `setSpeedDrop` |
| 速降落地且 `yPos === groundYPos` | `update()` 尾段 | `speedDrop=false; setDuck(true)` | `trex.ts` · `update` |
| 碰撞 | `gameOver()` | `crashed=true`，`stop()`（`paused=true; raqId=0`），`tRex.update(100, CRASHED)` | `offline.ts` · `gameOver` |
| `crashed` | keyup: Enter(13) / 画布左键 pointerup / (jump 键 且 `now - time >= gameoverClearTime`) | `handleGameOverClicks` → `restart()` | `offline.ts` · `onKeyUp` |
| `paused && !crashed` | keyup jump 键 | `tRex.reset(); play()` | `offline.ts` · `onKeyUp` |
| 失焦/隐藏 | `onVisibilityChange` | `stop()`；恢复时 `tRex.reset(); play()` | `offline.ts` · `onVisibilityChange` |

### 14.4 撞击后多久可以重开

```js
// offline.ts · gameOver
this.time = getTimeStamp();
// offline.ts · onKeyUp
} else if (this.crashed) {
  const deltaTime = getTimeStamp() - this.time;
  if (this.isCanvasInView() &&
      (runnerKeycodes.restart.includes(keyCode) ||            // Enter 13：立刻
       this.isLeftClickOnCanvas(e) ||                          // 画布左键 pointerup：立刻
       (deltaTime >= this.config.gameoverClearTime &&          // 1200 ms
        runnerKeycodes.jump.includes(keyCode)))) {             // 之后空格/↑ 才有效
    this.handleGameOverClicks(e);
  }
}
```

- **Enter** 和 **画布左键**：无延迟。
- **空格 / ↑**：必须等 `>= gameoverClearTime = 1200 ms`。
- 重开路径走的是 **keyup**（不是 keydown）。
- `restart()` 自身还有 `if (!this.raqId)` 守卫。

### 14.5 重开后重置的量（`offline.ts` · `restart`）

```js
restart() {
  if (!this.raqId) {
    this.playCount++;
    this.runningTime = 0;
    this.setPlayStatus(true);
    this.toggleSpeed();
    this.paused = false;
    this.crashed = false;
    this.distanceRan = 0;
    this.setSpeed(this.config.speed);
    this.time = getTimeStamp();
    this.containerEl.classList.remove('crashed');
    this.clearCanvas();
    this.distanceMeter.reset();     // → this.update(0, 0); this.achievement = false;
    this.horizon.reset();           // → obstacles = []; 每条 horizonLine.reset(); nightMode.reset();
    this.tRex.reset();              // → xPos=xInitialPos, yPos=groundYPos, jv=0, jumping/ducking/speedDrop=false,
                                    //   update(0,RUNNING), jumpCount=0
    this.playSound(this.soundFx.BUTTON_PRESS);
    this.invert(true);              // 清除 inverted class, invertTimer=0, inverted=false
    this.update();
    this.gameOverPanel.reset();
    ...
  }
}
```

**不重置的量：** `highestScore`、`activated`（保持 true，所以重开不再播 intro 宽度动画）、`playCount`、`obstacleHistory`（`horizon.reset()` 只清 `obstacles`，**不清 `obstacleHistory`**）。

> ⚠ `horizon.reset()` 里没有清 `obstacleHistory` / `obstacleTypes` — 重开后去重历史会**延续上一局**。

### 14.6 游戏结束判定与动画

```js
// offline.ts · gameOver
this.playSound(this.soundFx.HIT);
vibrate(200);                                  // 移动端 navigator.vibrate(200)
this.stop();
this.crashed = true;
this.distanceMeter.achievement = false;
this.tRex.update(100, TrexStatus.CRASHED);     // deltaTime 固定 100
// → GameOverPanel 首次创建并 draw()
if (this.distanceRan > this.highestScore) { this.saveHighScore(this.distanceRan); }
this.time = getTimeStamp();
this.showSpeedToggle();
this.disableSpeedToggle(false);
```

`game_over_panel.ts`：
- `draw()` → `drawGameOverText(defaultPanelDimensions, false)` → `drawRestartButton()` → `update()`。
- 文字目标位置：`textTargetX = Math.round(canvasWidth/2 - 191/2)`，`textTargetY = Math.round((canvasHeight - 25)/3)`；源 `textSprite {655,2}` ldpi，源块 `textX 0, textY 13, 191×11`。
- 重开按钮动画：`currentFrame` 0→8，帧源 X `[0,36,72,108,144,180,216,252]`，`msPerFrame = 109.375`；`currentFrame === 0` 时先等 `LOGO_PAUSE_DURATION = 875 ms`。
- `restartTargetX = (canvasWidth/2) - (restartHeight/2)` ← **当前版本用的是 `restartHeight`**（见 §17 差异表）；`restartTargetY = canvasHeight/2`；尺寸 `36×32`，源 `restart {2,68}` ldpi。

---

## 15. 输入映射（精确）

### 15.1 事件路由（`offline.ts` · `handleEvent`）

```js
switch (e.type) {
  case 'keydown': case 'touchstart': case 'pointerdown': this.onKeyDown(e); break;
  case 'keyup':   case 'touchend':   case 'pointerup':   this.onKeyUp(e);   break;
  case 'gamepadconnected': this.onGamepadConnected(); break;
}
```

监听器注册（`startListening`）：
- `containerEl`: `keydown`(→`handleCanvasKeyPress`), `focus`(→`showSpeedToggle`), `touchstart`
- `canvas`: `keydown`/`keyup` → `preventScrolling`（只对 `keyCode === 32` 调 `preventDefault`）
- `document`: `keydown`, `keyup`, `pointerdown`, `pointerup`
- 移动端首次 touchstart 才创建 `touchController` 并绑 `touchstart`/`touchend`

### 15.2 keydown（`onKeyDown`）

| 输入 | 条件 | 动作 |
|---|---|---|
| `ArrowUp` (38) / `Space` (32) | `!crashed && !paused` 且画布在视口内 | `preventDefault()`；若 `!playing` → 初始化开局；若 `!tRex.jumping && !tRex.ducking` → `tRex.startJump(currentSpeed)` |
| `touchstart` | 同上 | 同 jump 键（并可能创建 touchController） |
| `pointerdown` + `pointerType === 'mouse'` 且目标为 `containerEl`（iOS 还允许 touchController/canvas） | 仅 `IS_MOBILE` | 同 jump 键，且额外调 `handleCanvasKeyPress(e)` |
| `ArrowDown` (40) | `playing` | `preventDefault()`；`tRex.jumping` → `setSpeedDrop()`；否则 `!jumping && !ducking` → `setDuck(true)` |
| — | `e.target === slowSpeedCheckbox` 且是 jump 键 | 直接 `return`（让复选框工作） |

首次开局的完整副作用：
```js
this.loadSounds();
this.setPlayStatus(true);       // playing = true
this.update();                  // 立刻跑一帧
window.errorPageController?.trackEasterEgg();
```

### 15.3 keyup（`onKeyUp`）——**speed drop 的关键在这里之前，`endJump` 在这里**

```js
private onKeyUp(e) {
  const keyCode = ('keyCode' in e) ? e.keyCode : 0;
  const isjumpKey = runnerKeycodes.jump.includes(keyCode) ||
      e.type === 'touchend' || e.type === 'pointerup';

  if (this.isRunning() && isjumpKey) {              // isRunning() = !!this.raqId
    this.tRex.endJump();                            // ← 松 jump 键 → 提前结束上升
  } else if (runnerKeycodes.duck.includes(keyCode)) {   // 40
    this.tRex.speedDrop = false;                    // ← 松 ↓：取消速降
    this.tRex.setDuck(false);                       // ← 起身
  } else if (this.crashed) {
    /* §14.4 重开逻辑 */
  } else if (this.paused && isjumpKey) {
    this.tRex.reset();
    this.play();
  }
}
```

### 15.4 映射总表

| 输入 | keydown | keyup |
|---|---|---|
| `Space` (32) | 起跳 / 开局 | `endJump()` |
| `ArrowUp` (38) | 起跳 / 开局 | `endJump()` |
| `ArrowDown` (40) | 空中→`setSpeedDrop()`；地面→`setDuck(true)` | `speedDrop=false` + `setDuck(false)` |
| `Enter` (13) | 无 | 撞毁后立刻 `restart()` |
| 鼠标左键按下 (`pointerdown`) | 移动端：起跳/开局 | — |
| 鼠标左键松开 (`pointerup`) | — | `endJump()`；撞毁时若在 canvas 上则 `restart()` |
| `touchstart` | 起跳 / 开局 | — |
| `touchend` | — | `endJump()` |
| `click` | 未使用（`RunnerEvents.CLICK` 定义了但没注册监听） | — |
| 手柄 (`gamepadconnected`，仅 arcade 模式) | 按钮 0→38、按钮 1→40、按钮 9→13 | 同左（按下沿/抬起沿合成 KeyboardEvent） |

> `RunnerEvents.CLICK` / `TOUCHSTART` 在 `document` 上**没有**注册；`TOUCHSTART` 只注册在 `containerEl` 和 `touchController` 上。

---

## 16. 精灵表引用总览（复刻画图时用）

设 `IS_HIDPI === false`（1x 图），所有坐标格式 `(源X, 源Y, 源W, 源H) → (目标X, 目标Y, 目标W, 目标H)`。

| 元素 | 源 | 目标 |
|---|---|---|
| T-Rex 跑/站/跳/撞 | `(848 + frame, 2, 44, 47)` | `(xPos, yPos, 44, 47)` |
| T-Rex 下蹲 | `(848 + 264或323, 2, 59, 47)` | `(xPos, 93, 59, 47)` |
| 仙人掌小 | `(228 + {0,17,51}, 2, 17*size, 35)` | `(xPos, 105, 17*size, 35)` |
| 仙人掌大 | `(332 + {0,25,75}, 2, 25*size, 50)` | `(xPos, 90, 25*size, 50)` |
| 翼龙 | `(134 + 46*frame, 2, 46, 40)` | `(xPos, yPos, 46, 40)` |
| 云 | `(86, 2, 46, 14)` | `(xPos, yPos, 46, 14)` |
| 地面 | `(2 或 602, 52, 600, 12)` | `(xPos[i], 127, 600, 12)` |
| 数字 0-9 / H / I | `(655 + 10*d, 2, 10, 13)`，`H=10, I=11` | `(baseX + i*11, 5, 10, 13)` |
| 月亮 | `(484 + PHASES[phase], 2, 20或40, 40)` | `(round(xPos), 30, 20或40, 40)` |
| 星星 | `(645, 2 + 9*i, 9, 9)` | `(round(star.x), star.y, 9, 9)` |
| GAME OVER 文字 | `(655 + 0, 2 + 13, 191, 11)` | `(round(cw/2 - 95.5), round((ch-25)/3), 191, 11)` |
| 重开按钮 | `(2 + frame, 68, 36, 32)` | `(cw/2 - 16, ch/2, 36, 32)` |

T-Rex 帧偏移（相对 `tRex.x = 848`）：`JUMPING 0`、`WAITING1 44`、`WAITING2 0`、`RUNNING1 88`、`RUNNING2 132`、`CRASHED 220`、`DUCKING1 264`、`DUCKING2 323`。

---

## 17. 当前版本 vs 旧版经典 `offline.js`（重要）

**对比基准：**
- 「当前」= `chromium/chromium@main` 的 `dino_game/*.ts`（全部逐字核对 ✅）
- 「旧版」= `chromium/chromium@120.0.6099.109` 的 `components/neterror/resources/offline.js` + `offline-sprite-definitions.js`
  （`offline.js` 只逐字核对了**首段与尾段**；`offline-sprite-definitions.js` **完整**核对）

### 17.1 ✅ 逐字核对：**完全相同**的数值

| 参数 | 旧版 `offline.js` | 当前 `dino_game/` | 出处 |
|---|---|---|---|
| `Runner.config.INITIAL_JUMP_VELOCITY` | `12` | `12` | `defaultBaseConfig.initialJumpVelocity` |
| `Trex.normalJumpConfig.INITIAL_JUMP_VELOCITY` | `-10` | `-10` | `normalJumpConfig` |
| `Trex.normalJumpConfig.GRAVITY` | `0.6` | `0.6` | 同上 |
| `Trex.normalJumpConfig.MAX_JUMP_HEIGHT` | `30` | `30` | 同上 |
| `Trex.normalJumpConfig.MIN_JUMP_HEIGHT` | `30` | `30` | 同上 |
| `Trex.slowJumpConfig` | `{0.25, 50, 45, -20}` | `{0.25, 50, 45, -20}` | `slowJumpConfig` |
| `Trex.config.DROP_VELOCITY` | `-5` | `-5` | `defaultTrexConfig.dropVelocity` |
| `Trex.config.SPEED_DROP_COEFFICIENT` | `3` | `3` | `defaultTrexConfig.speedDropCoefficient` |
| `Trex.config.HEIGHT` / `HEIGHT_DUCK` | `47` / `25` | `47` / `25` | 同上 |
| `Trex.config.WIDTH` / `WIDTH_DUCK` | `44` / `59` | `44` / `59` | 同上 |
| `Trex.config.START_X_POS` | `50` | `50` | 同上 |
| `Trex.config.SPRITE_WIDTH` | `262` | `262` | 同上 |
| `Trex.config.INTRO_DURATION` | `1500` | `1500` | 同上 |
| `Trex.config.FLASH_ON` / `FLASH_OFF` | `100` / `175` | `100` / `175` | 同上 |
| `Trex.BLINK_TIMING` | `7000` | `7000` | 模块级 `BLINK_TIMING` |
| `Trex.collisionBoxes.DUCKING` | `[(1,18,55,25)]` | `[(1,18,55,25)]` | `collisionBoxes.ducking` |
| `Trex.collisionBoxes.RUNNING` | 6 个盒，值完全一致 | 同 | `collisionBoxes.running` |
| `Trex.animFrames` 五档 | `WAITING [44,0] 1000/3`、`RUNNING [88,132] 1000/12`、`CRASHED [220] 1000/60`、`JUMPING [0] 1000/60`、`DUCKING [264,323] 1000/8` | 同 | `animFrames` |
| `Obstacle.MAX_GAP_COEFFICIENT` | `1.5` | `1.5` | `maxGapCoefficient` |
| `Obstacle.MAX_OBSTACLE_LENGTH` | `3` | `3` | `maxObstacleLength` |
| `Runner.config` 全部字段 | `AUDIOCUE…190/250, BG_CLOUD_SPEED 0.2, BOTTOM_PAD 10, CANVAS_IN_VIEW_OFFSET -10, CLEAR_TIME 3000, CLOUD_FREQUENCY 0.5, FADE_DURATION 1, FLASH_DURATION 1000, GAMEOVER_CLEAR_TIME 1200, INITIAL_JUMP_VELOCITY 12, INVERT_FADE_DURATION 12000, MAX_BLINK_COUNT 3, MAX_CLOUDS 6, MAX_OBSTACLE_LENGTH 3, MAX_OBSTACLE_DUPLICATION 2, SPEED 6, SPEED_DROP_COEFFICIENT 3, ARCADE_MODE_INITIAL_TOP_POSITION 35, ARCADE_MODE_TOP_POSITION_PERCENT 0.1` | 同 | `defaultBaseConfig` |
| `Runner.normalConfig` | `{0.001, 0.6, 700, 13, 1.2, 6}` | 同 | `normalModeConfig` |
| `Runner.slowConfig` | `{0.0005, 0.3, 350, 9, 1.5, 4.2}` | 同 | `slowModeConfig` |
| `Runner.defaultDimensions` | `{WIDTH:600, HEIGHT:150}` | `DEFAULT_DIMENSIONS {600,150}` | `constants.ts` |
| `FPS` | `60` | `60` | `constants.ts` |
| `Runner.keycodes` | `JUMP {38,32}, DUCK {40}, RESTART {13}` | 同 | `runnerKeycodes` |
| 障碍数值（small/large/pterodactyl 的 width/height/yPos/minGap/minSpeed/multipleSpeed/speedOffset/frameRate/collisionBoxes） | 与当前 TS **逐字段相同** | 同 | `offline-sprite-definitions.js` vs `offline_sprite_definitions.ts` |
| `Obstacle.init` / `getGap` / `update` / `draw` / `cloneCollisionBoxes` | 与当前 TS **逐行相同** | 同 | 逐字核对 |
| `checkForCollision` / `createAdjustedCollisionBox` / `drawCollisionBoxes` / `boxCompare` | 与当前 TS 相同（旧版 `boxCompare` 用 `let crashed` 的写法，逻辑等价） | 同 | 逐字核对 |
| `MAX_GAP_COEFFICIENT 1.5` / `MAX_OBSTACLE_LENGTH 3` / `HAS_CLOUDS 1` / `BOTTOM_PAD 10` | 同 | 同 | 逐字核对 |
| `LINES [{2,52,600,12,127}]` | 同 | 同 | 逐字核对 |
| `LDPI/HDPI` 精灵坐标（除下表两行外） | 同 | 同 | 逐字核对 |

**➡ 关于「`initialJumpVelocity` 当前是 -10 而旧版是 -12」：这是误解。**
我在 **120.0.6099.109**（2023-12）里逐字核对到的是 `Trex.normalJumpConfig.INITIAL_JUMP_VELOCITY: -10`，与当前 `main` **完全一致**。
`12` 这个数字确实存在，但含义不同：
- `Runner.config.INITIAL_JUMP_VELOCITY: 12`（正数，旧版与当前都有）—— 这是**调试入口**的默认值；
- `Trex.setJumpVelocity(setting)` 会把它取负并派生下落速度：
  ```js
  setJumpVelocity(setting) {
    this.config.initialJumpVelocity = -setting;
    this.config.dropVelocity = -setting / 2;
  }
  ```
  即 `setJumpVelocity(12)` 得到 `initialJumpVelocity = -12, dropVelocity = -6`。**只在 `updateTrexConfigSetting('initialJumpVelocity', v)`（调试）时才会走到。**
- 正常玩法的起跳速度永远是 `normalJumpConfig.initialJumpVelocity (-10) - currentSpeed/10`。

我**没有**追溯到 2014–2019 的历史版本（见 §0 的取用限制），所以不能断言"历史上从未出现过 -12"。但可以确定：**-10 不是新版本才改的，它在 120.x 就已经是 -10；-12 在 120.x 与 main 里都不是正常玩法的起跳初速。**

### 17.2 ✅ 逐字核对：**确有差异**的地方

| 项 | 旧版 120.0.6099.109 | 当前 main | 影响 |
|---|---|---|---|
| `spriteDefinitionByType.original.ldpi.collectable` | `{x: 2, y: 2}` | `{x: 0, y: 0}` | 仅 alt game 模式 |
| `...hdpi.collectable` | `{x: 4, y: 4}` | `{x: 0, y: 0}` | 仅 alt game 模式 |
| `...ldpi.altGameEnd` | `{x: 121, y: 2}` | `{x: 32, y: 0}` | 仅 alt game 模式 |
| `...hdpi.altGameEnd` | `{x: 242, y: 4}` | `{x: 64, y: 0}` | 仅 alt game 模式 |
| `OBSTACLES` 数组 | 3 项：`CACTUS_SMALL, CACTUS_LARGE, PTERODACTYL`（**无 `collectable`**） | 4 项：多出 `collectable {31,24,104,1000,9999,0,...}` | 默认玩法都走 `obstacleCount = len-2 = 2`，**索引范围 {0,1,2} 相同**，行为一致 |
| `BACKGROUND_EL['CLOUD']` 结构 | 含 `MAX_CLOUD_GAP 400, MAX_SKY_LEVEL 30, MIN_CLOUD_GAP 100, MIN_SKY_LEVEL 71, OFFSET 4, WIDTH 46, HEIGHT 14, X_POS 1, Y_POS 120`（云参数写在精灵定义里） | 云参数移到 `cloud.ts` 的 `Config`；精灵定义里只剩 `{height:14, offset:4, width:46, xPos:1, fixed:false}`；`Y_POS` 移到 `backgroundElConfig.yPos = 125` | **数值等价**（云实际用 `cloud.ts` 的常量）；`Y_POS 120` 在旧版是 `BackgroundEl` 用的，当前用 `yPos 125` —— 只影响 alt 模式的背景元素 |
| `GameOverPanel.drawRestartButton` 的 `restartTargetX` | `(canvasWidth / 2) - (dimensions.RESTART_WIDTH / 2)` = `cw/2 - 18` | `(canvasWidth / 2) - (dimensions.restartHeight / 2)` = **`cw/2 - 16`** | **可见的 2 px 位移差异**。当前版本这里用的是 `restartHeight`（疑似笔误），复刻"当前 Chrome"就用 `-16` |
| 字体/模块化 | 单文件 `offline.js`（`Runner`/`DistanceMeter`/`Horizon`/`NightMode`/`Cloud`/`Trex`/`Obstacle`/`GameOverPanel` 全在一个文件） | 拆成 14 个 TS 模块 + 依赖注入接口（`ConfigProvider` 等） | 结构差异，数值不变 |
| `Runner` 构造 | 函数式 `export function Runner(id, opt_config)` + `Runner.prototype = {...}`，单例 `Runner.instance_` | `class Runner` + `static initializeInstance()` / `static getInstance()` | 结构差异 |
| `Obstacle.update` 里的 `FPS` 引用 | 模块级 `const FPS = 60` | `import {FPS} from './constants.js'` | 数值相同 |

### 17.3 ❓ 未能逐字核对的旧版片段（**不做断言**）

以下旧版 `offline.js` 的**函数体**落在 GitHub API 返回被截断的中间段，我**没有**原文：

- `Runner.prototype.update`（因此我**不能**断言旧版是否对 `deltaTime` 做上限裁剪；当前版本是**没有**裁剪）
- `DistanceMeter` 的完整实现（`COEFFICIENT: 0.025` / `MAX_DISTANCE_UNITS: 5` / `ACHIEVEMENT_DISTANCE: 100` / `FLASH_DURATION: 1000/4` / `FLASH_ITERATIONS: 3` 这些值在当前 TS 中确认，旧版未能逐字读到）
- `Horizon.prototype`（`updateObstacles` / `addNewObstacle` / `duplicateObstacleCheck` / `updateClouds`）—— 但旧版的 `Obstacle.getGap` 我读到了，公式与当前一致
- `NightMode` / `Cloud` / `GameOverPanel` 的完整实现
- `Utils.getRandomNum`（当前 TS 是 `Math.floor(Math.random() * (max - min + 1)) + min`）

如果你需要这几段的历史对照，建议在一台能正常执行命令的机器上 `git clone --filter=blob:none chromium` 或直接打开
`https://chromium.googlesource.com/chromium/src/+/refs/tags/120.0.6099.109/components/neterror/resources/offline.js`。
我这边 `chromium.googlesource.com` / `raw.githubusercontent.com` 均不可达（见 §0）。

---

## 18. 对复刻实现的提醒（最容易在像素级复刻中出错的点）

按"影响手感程度"排序：

### 1. `Math.round` 的位置与 JS 的舍入语义（最容易错，影响最大）
`trex.ts · updateJump`：
```js
yPos += Math.round(jumpVelocity * framesElapsed);
```
- `Math.round` **只包住 `jumpVelocity * framesElapsed`**，不动 `jumpVelocity`，也不动 `yPos`。
- JS 的 `Math.round` 是"**向 +∞ 方向的 .5 舍入**"：`Math.round(-10.5) = -10`，`Math.round(-0.5) = -0`。
- **PowerShell 的 `[Math]::Round()` 默认是银行家舍入（ToEven）**，必须改写成 `[Math]::Floor($x + 0.5)` 才等价。
- 若写成 `yPos += jumpVelocity * framesElapsed`（不取整），`yPos` 变成小数，碰撞盒外层的 `-2` 与子盒整数偏移会随之漂移，手感与判定立刻不同。
- 同理 `obstacle.ts`/`horizon_line.ts` 用的是 `Math.floor`，`cloud.ts` 用的是 `Math.ceil` —— **三者取整方向不同，不能统一**。

### 2. 起跳初速度里的速度修正项
```js
jumpVelocity = this.config.initialJumpVelocity - (speed / 10);   // -10 - speed/10
```
- `speed` 是**起跳那一帧的 `currentSpeed`**（已经包含本帧之前的全部 `+0.001`）。
- 从 `-10.6`（speed=6）到 `-11.3`（speed=13），差值 0.7。忽略这一项，后期跳跃会明显偏低、节奏全错。
- 注意**只有起跳用速度修正，`endJump` 的 `dropVelocity = -5` 是常数**。

### 3. `maxJumpHeight` 判定用的是**裸配置值 30**，而 `minJumpHeight` 用的是**绝对值 63**
```js
minJumpHeight = groundYPos - config.minJumpHeight = 93 - 30 = 63;   // 构造时算好
...
!invertJump && (this.yPos < this.config.maxJumpHeight)              // → yPos < 30，不是 yPos < 63
```
- 如果你"顺手"把 `maxJumpHeight` 也换算成 `groundYPos - 30 = 63`，跳跃峰值会被砍掉一大截（峰值 yPos≈2 → 会更早触发 `endJump`）。
- 这个不对称是**原版就有的**，照抄才能一致。

### 4. `endJump` 的两个门槛：`reachedMinHeight` + `jumpVelocity < dropVelocity`
```js
if (this.reachedMinHeight && this.jumpVelocity < this.config.dropVelocity) {
  this.jumpVelocity = this.config.dropVelocity;   // -5
}
```
- **短按在未达最小高度前完全无效**（不是"缩短跳跃"，而是"什么都不做"）。很多人实现成"松键就加速下落"，那是另一个游戏。
- 松键只在 **keyup**（以及 touchend / pointerup）触发，不在 keydown。**按住期间没有任何额外高度增益**——所谓"长按跳更高"只是因为**松得晚 → `-5` 钳制来得晚**。

### 5. gap 公式里**没有画布宽度**，但生成门限里有
```js
minGap = Math.round(width * speed + typeConfig.minGap * gapCoefficient);
maxGap = Math.round(minGap * 1.5);
gap    = Math.floor(Math.random() * (maxGap - minGap + 1)) + minGap;
// 生成门限（在 horizon.ts 里）：
(lastObstacle.xPos + lastObstacle.width + lastObstacle.gap) < this.dimensions.width
```
- `width` 在这里是 **`typeConfig.width * size`**（多连体越宽 → gap 越大）。
- `speed` 是**障碍创建瞬间**的速度，之后不再更新（gap 是"冻结"的）。
- `gapCoefficient` 默认 0.6；`Obstacle` 构造里还会 `hasSlowdown ? *2 : *1`。
- 画布宽度只影响"什么时候可以放下一个"，**不影响 gap 数值**。把画布宽度乘进 gap 公式是常见错误，会让窄屏/宽屏节奏全变。
- 障碍初始 X 是 `canvasWidth + typeConfig.width`（**不是** `canvasWidth`，也**不是** `width*size`）。

### 6. 碰撞盒的 `+1 / -2` 白边修正 + 下蹲时外层盒仍用 `config.width`
```js
tRexBox     = (xPos+1, yPos+1, config.width - 2, config.height - 2);   // 下蹲也用 width=44！
obstacleBox = (xPos+1, yPos+1, typeConfig.width*size - 2, typeConfig.height - 2);
adjBox      = (子盒.x + 外层盒.x, 子盒.y + 外层盒.y, 子盒.w, 子盒.h);
```
- 子盒绝对坐标是 `子盒 + (xPos+1, yPos+1)`，这个 `+1` 极易漏掉。
- **下蹲时**子盒是 `(1,18,55,25)`，但外层盒还是 `44-2 = 42` 宽 → 实际横向命中区被裁到约 41 px，而不是 55 px。照抄才能得到一样的"擦边不死"手感。
- 判定用**严格不等号**，无 padding，无容差。边界相切不算碰撞。

### 7. 障碍数组用 `shift()` 移除（而不是按 `remove` 过滤）
```js
for (const obstacle of this.obstacles) {
  obstacle.update(deltaTime, currentSpeed);
  if (obstacle.remove) { updatedObstacles.shift(); }   // ← 删的是队首
}
```
- 翼龙有 `speedOffset = ±0.8`，会与仙人掌换位；此时 `shift()` 会剔除错误的元素。
- 想 100% 复刻 Chrome（包括这个偶发 bug），就照抄 `shift()`；想"更正确"就按 `remove === true` 过滤——但那样行为与 Chrome 不一致。

### 8. 每帧只生成一个障碍 + `followingObstacleCreated` 互锁
- 不要按速度一次生成多个填满屏幕。
- 生成条件是"最后一个障碍的 `xPos + width + gap < canvasWidth`"，且该障碍的 `followingObstacleCreated` 还没被置位。
- 开局要先等 `runningTime > clearTime (3000 ms)` 才允许有障碍（`hasObstacles`），同时 `hasObstacles` 也是碰撞检测和距离累加的前置条件。

### 9. 距离/分数链路里的两次取整方向不同
```
distanceRan += currentSpeed * deltaTime / (1000/60)
distanceMeter.update(deltaTime, Math.ceil(distanceRan))       // ← ceil
score = Math.round(Math.ceil(distanceRan) * 0.025)            // ← round
```
- 是 `Math.ceil(distanceRan)` 之后才乘 `0.025` 再 `Math.round`，不是 `Math.round(distanceRan * 0.025)` 一步到位（大多数情况下结果相同，但在 `distanceRan` 的小数部分接近下一个整数时会差 1 分）。
- `distanceRan === 0` 时 `getActualDistance` 直接返回 `0`（不取 round）。

### 10. 速度增长是**按帧**而不是按时间
```js
if (currentSpeed < maxSpeed) currentSpeed += acceleration;   // +0.001 / 帧，与 deltaTime 无关
```
- 60fps 下约 116.7 秒到顶；如果按 `deltaTime` 缩放成"每秒 +0.06"，在非 60fps（或掉帧）时速度曲线会与 Chrome 分叉。
- `currentSpeed` 只在 `!collision` 时增长，且**在 `horizon.update` 之后**才增长（本帧障碍用旧速度）。
- 重开用 `setSpeed(config.speed)`；画布宽度 < 600 时会被压到 `speed * width/600 * 1.2`（取 min）。

### 11. 里程碑闪烁期间的"分数冻结"是显示层的，不是逻辑层的
- `distanceRan` 照常累加，只是 `distanceMeter.digits` 在 `achievement === true` 期间不刷新。
- 闪烁是 `250 ms 隐藏 / 250 ms 显示` 的切换，条件是 `flashTimer < 250`（隐藏）与 `flashTimer > 500`（重置并 `flashIterations++`），`flashIterations <= 3`。
- 用 `>` 而不是 `>=`，用 `<` 而不是 `<=`，这些边界决定了闪烁次数是 3 还是 4 次。

### 12. 时间步进没有上限裁剪
- `deltaTime = now - (this.time || now)`，首次为 0。
- 掉帧/标签页卡顿会产生巨大的 `deltaTime`，直接乘以 `currentSpeed` 推进距离、`framesElapsed` 推进跳跃。
- Chrome 靠 `blur` / `visibilitychange` → `stop()` 来避免大部分这种情况；复刻时要么同样处理，要么明确决定是否加裁剪（加了就与 Chrome 不同）。
