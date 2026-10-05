#Requires -Version 5.1
<#
    ChromeDino.ps1 —— 终端版「谷歌小恐龙」(T-Rex Runner) 逐帧复刻

    机制来源：Chromium 官方源码 components/neterror/resources/dino_game/
              （offline.ts / trex.ts / obstacle.ts / horizon.ts / distance_meter.ts）
              本脚本的每一个数值与公式都照抄该源码，细节见同目录 chrome-dino-spec.md。

    兼容性：Windows PowerShell 5.1 与 PowerShell 7.x 均可运行。
    运行：  powershell -ExecutionPolicy Bypass -File .\ChromeDino.ps1
            pwsh -File .\ChromeDino.ps1
    自测：  pwsh -File .\ChromeDino.ps1 -Simulate        # 无界面跑物理自检

    操作：  空格 / ↑  起跳（按住不松 = 跳更高，松手 = 提前结束上升）
            ↓        地面下蹲；空中速降
            Enter    撞毁后立刻重开（空格/↑ 需等 1200ms）
            Esc      退出
#>
[CmdletBinding()]
param(
    # 逻辑画布宽度（像素）。原版 600；终端更窄时会自动缩小并按原版规则缩放速度。
    [ValidateRange(180, 6000)][int]$CanvasWidth = 900,
    # 只用 ASCII 字符渲染（老终端 / 不支持半块字符时）
    [switch]$Ascii,
    # 关闭颜色
    [switch]$NoColor,
    # 无界面自检：跑物理测试并打印结果
    [switch]$Simulate,
    # 自检的模拟帧数
    [int]$SimulateFrames = 20000,
    # 无界面渲染快照 + 机器人试玩（用于验证画面与长跑稳定性）
    [switch]$Dump,
    [int]$DumpFrames = 3400,
    # 只在终端窗口处于前台时才响应按键（默认关闭：GetAsyncKeyState 是全局状态，
    # 开着会在你切到别的窗口打字时误触发；但焦点判断在某些终端里不可靠，故做成可选）
    [switch]$FocusOnly,
    # 渲染模式：auto 自动探测 / braille 盲文点阵（最细腻）/ block 半块 ▀▄█ / ascii 纯 ASCII（最保险）
    [ValidateSet('auto', 'braille', 'block', 'ascii')][string]$Render = 'auto',
    # 打印三种字符集的样本，用来确认你的终端到底能显示哪一种
    [switch]$GlyphTest
)

$ErrorActionPreference = 'Stop'

# ── 运行方式自检 ─────────────────────────────────────────────────────────────
# 把脚本内容「粘贴到控制台」执行时，上面的 param(...) 不会生效，$CanvasWidth 会是空值，
# 于是画布宽度算成 0 → 无论窗口多宽都会误报「终端太窄」。这里兜底并给出正确用法。
$PastedIntoConsole = -not $PSCommandPath
if (-not $CanvasWidth -or $CanvasWidth -lt 180) { $CanvasWidth = 600 }
if ($PastedIntoConsole) {
    Write-Host ''
    Write-Host '注意：你是把脚本内容粘贴进控制台执行的。这样能跑，但参数（-Ascii/-Dump 等）不会生效，' -ForegroundColor Yellow
    Write-Host '而且每次都要重新粘贴。建议改用脚本文件方式运行：' -ForegroundColor Yellow
    Write-Host '    cd D:\Test_DSH' -ForegroundColor Cyan
    Write-Host '    pwsh -ExecutionPolicy Bypass -File .\ChromeDino.ps1' -ForegroundColor Cyan
    Write-Host '（下面仍然继续启动游戏）' -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
}

#region ── 原版常量（逐个照抄，勿改） ────────────────────────────────────────────
$C = @{
    FPS                    = 60
    ACCELERATION           = 0.0007     # 每帧 +0.0007（按帧，不按时间）→ 6→15 约 12858 帧 ≈ 3.6 分钟
    MAX_SPEED              = 20.0
    SPEED                  = 6.0
    GAP_COEFFICIENT        = 0.6
    MAX_GAP_COEFFICIENT    = 1.5
    INVERT_DISTANCE        = 700
    MAX_OBSTACLE_LENGTH    = 3
    MAX_OBSTACLE_DUPLICATION = 2
    CLEAR_TIME             = 3000       # 开局 3 秒内不生成障碍
    GAMEOVER_CLEAR_TIME    = 1200       # 撞毁后空格/↑ 需等这么久
    BOTTOM_PAD             = 10
    CANVAS_HEIGHT          = 150
    MOBILE_SPEED_COEFF     = 1.2

    TREX_WIDTH             = 44
    TREX_HEIGHT            = 47
    TREX_WIDTH_DUCK        = 59
    TREX_HEIGHT_DUCK       = 25
    TREX_START_X           = 50
    GRAVITY                = 0.6
    INITIAL_JUMP_VELOCITY  = -10.0
    MAX_JUMP_HEIGHT        = 30         # ⚠ 判定用裸值 30（不是 groundY-30）
    MIN_JUMP_HEIGHT_CFG    = 30         # 派生 minJumpHeight = 93-30 = 63
    DROP_VELOCITY          = -5.0
    SPEED_DROP_COEFFICIENT = 3
    MAX_BLINK_COUNT        = 3
    BLINK_TIMING           = 7000

    MAX_DISTANCE_UNITS     = 5
    ACHIEVEMENT_DISTANCE   = 100
    SCORE_COEFFICIENT      = 0.025
    FLASH_DURATION         = 250        # 1000/4
    FLASH_ITERATIONS       = 3
}
$C.MS_PER_FRAME = 1000.0 / $C.FPS              # 16.6666…
$C.GROUND_Y     = $C.CANVAS_HEIGHT - $C.TREX_HEIGHT - $C.BOTTOM_PAD   # 93
$C.MIN_JUMP_Y   = $C.GROUND_Y - $C.MIN_JUMP_HEIGHT_CFG                # 63（绝对值）

# 状态枚举（照抄 trex.ts）
$STATUS_CRASHED = 0
$STATUS_DUCKING = 1
$STATUS_JUMPING = 2
$STATUS_RUNNING = 3
$STATUS_WAITING = 4

# 障碍类型。注意：原版数组有 4 项，第 4 项 'collectable' 在默认玩法下被
# obstacleCount = len-2 = 2 排除（索引域仍是 0..2），故此处只建 3 项，取值域等价。
$ObstacleTypes = @(
    @{ type = 'cactusSmall'; width = 17; height = 35; yPos = 105; yPosMobile = $null
       multipleSpeed = 4;   minGap = 120; minSpeed = 0.0; numFrames = 0; frameRate = 0.0; speedOffset = 0.0
       boxes = @(@(0, 7, 5, 27), @(4, 0, 6, 34), @(10, 4, 7, 14)) },
    @{ type = 'cactusLarge'; width = 25; height = 50; yPos = 90;  yPosMobile = $null
       multipleSpeed = 7;   minGap = 120; minSpeed = 0.0; numFrames = 0; frameRate = 0.0; speedOffset = 0.0
       boxes = @(@(0, 12, 7, 38), @(8, 0, 7, 49), @(13, 10, 10, 38)) },
    @{ type = 'pterodactyl'; width = 46; height = 40; yPos = @(100, 75, 50); yPosMobile = @(100, 50)
       multipleSpeed = 999; minGap = 150; minSpeed = 8.5; numFrames = 2; frameRate = (1000.0 / 6); speedOffset = 0.8
       boxes = @(@(15, 15, 16, 5), @(18, 21, 24, 6), @(2, 14, 4, 3), @(6, 10, 4, 7), @(10, 8, 6, 9)) }
)

# T-Rex 碰撞子盒（trex.ts · collisionBoxes）
$TrexBoxesRunning = @(@(22, 0, 17, 16), @(1, 18, 30, 9), @(10, 35, 14, 8),
                      @(1, 24, 29, 5), @(5, 30, 21, 4), @(9, 34, 15, 4))
# ⚠ 单元素嵌套数组必须用一元逗号包住，否则外层 @() 会把内层拆成 4 个整数（宽高变 0）
$TrexBoxesDucking = @(, @(1, 18, 55, 25))
#endregion

#region ── 渲染常量 ─────────────────────────────────────────────────────────────
# 渲染网格：一个「点」= 4x4 逻辑像素（正方形 → 画面比例不会失真）。
# 一个字符 = 2 点宽 x 4 点高，用盲文点阵字符（U+2800..U+28FF）承载，
# 也就是每个字符里有 2x4=8 个可独立点亮的点，细节是半块方案的 8 倍。
# 若终端显示不了盲文点阵，会自动退回半块（▀▄█）或纯 ASCII，布局不变。
# ⚠ 只影响画面：物理与碰撞全部在 600x150 的逻辑像素空间里算，改这里不会动手感。
$PX_PER_DOT_X   = 3
$PX_PER_DOT_Y   = 3
$DOTS_PER_CHAR_X = 2        # 一个字符宽 = 2 个点
$DOTS_PER_CHAR_Y = 4        # 一个字符高 = 4 个点
$CH_HALF_UP    = [char]0x2580   # ▀
$CH_HALF_DOWN  = [char]0x2584   # ▄
$CH_FULL       = [char]0x2588   # █
$CH_SPACE      = [char]32
$CH_GROUND     = [char]0x2584
$CH_BLOCK_ASC  = '#'
#endregion

#region ── 随机数（照抄 utils.ts · getRandomNum：闭区间，均匀） ──────────────────
$script:Rng = New-Object System.Random
function Get-RandomNum([int]$min, [int]$max) {
    if ($max -lt $min) { return $min }
    return [int][Math]::Floor($script:Rng.NextDouble() * ($max - $min + 1)) + $min
}
# JS 的 Math.round 是「向 +∞ 的 .5 舍入」，PowerShell 的 [Math]::Round 是银行家舍入 → 必须改写
function Get-JsRound([double]$x) {
    return [int][Math]::Floor($x + 0.5)
}
#endregion

#region ── 游戏状态 ─────────────────────────────────────────────────────────────
$script:G = $null

function New-Game {
    param([int]$canvasW)

    $g = @{}
    $g.canvasW          = $canvasW
    $g.currentSpeed     = [double]$C.SPEED
    $g.distanceRan      = 0.0
    $g.runningTime      = 0.0
    $g.obstacles        = @()
    $g.obstacleHistory  = @()
    $g.activated        = $false
    $g.playing          = $false
    $g.crashed          = $false
    $g.crashTime        = 0.0
    $g.highestScore     = 0
    $g.jumpCount        = 0
    $g.inverted         = $false
    $g.invertTimer      = 0.0
    $g.obstaclesEnabled = $false
    $g.nextObstacleId   = 0
    Initialize-Sky

    $g.trex = @{
        xPos              = [double]$C.TREX_START_X
        yPos              = [double]$C.GROUND_Y
        jumping           = $false
        ducking           = $false
        speedDrop         = $false
        jumpVelocity      = 0.0
        reachedMinHeight  = $false
        minJumpHeight     = [double]$C.MIN_JUMP_Y
        status            = $STATUS_WAITING
        currentFrame      = 0
        timer             = 0.0
        blinkCount        = 0
        blinkDelay        = 1200.0
        blinkTimer        = 0.0
        blinking          = $false
        animStartTime     = 0.0
        msPerFrame        = $C.MS_PER_FRAME
        flashing          = $false
    }

    $g.meter = @{
        maxScoreUnits  = $C.MAX_DISTANCE_UNITS
        maxScore       = 99999
        digits         = @('0','0','0','0','0')
        score          = 0
        achievement    = $false
        flashTimer     = 0.0
        flashIterations = 0
        highScoreStr   = 'HI 00000'
    }
    return $g
}

function Reset-SpeedTo([double]$newSpeed) {
    # offline.ts · setSpeed：窄画布时按原版规则压低速度
    if ($script:G.canvasW -lt 600) {
        $mobile = $newSpeed * $script:G.canvasW / 600.0 * $C.MOBILE_SPEED_COEFF
        if ($mobile -gt $newSpeed) { $script:G.currentSpeed = $newSpeed }
        else                       { $script:G.currentSpeed = $mobile }
    } else {
        $script:G.currentSpeed = $newSpeed
    }
}
#endregion

#region ── T-Rex：跳跃 / 下蹲 / 动画（trex.ts） ─────────────────────────────────
function Update-TrexAnim([double]$deltaTime, [int]$status) {
    # trex.ts · update(deltaTime, status)
    $t = $script:G.trex
    $t.timer += $deltaTime
    if ($PSBoundParameters.ContainsKey('status')) {
        $t.status = $status
        $t.currentFrame = 0
        # 各自帧率（trex.ts · animFrames）
        if     ($status -eq $STATUS_WAITING) { $t.msPerFrame = 1000.0 / 3 }
        elseif ($status -eq $STATUS_RUNNING) { $t.msPerFrame = 1000.0 / 12 }
        elseif ($status -eq $STATUS_CRASHED) { $t.msPerFrame = 1000.0 / 60 }
        elseif ($status -eq $STATUS_JUMPING) { $t.msPerFrame = 1000.0 / 60 }
        elseif ($status -eq $STATUS_DUCKING) { $t.msPerFrame = 1000.0 / 8 }
        if ($status -eq $STATUS_WAITING) {
            $t.blinkDelay = [Math]::Ceiling($script:Rng.NextDouble() * $C.BLINK_TIMING)
            $t.animStartTime = 0.0
        }
    }
    # 眨眼（纯装饰：原版只在待机时眨，这里跑动时也眨，观感更活）
    $t.blinkTimer += $deltaTime
    if ($t.blinking) {
        if ($t.blinkTimer -ge 130) {
            $t.blinking = $false
            $t.blinkTimer = 0.0
            $t.blinkDelay = 1500.0 + ($script:Rng.NextDouble() * 2500.0)
        }
    } elseif ($t.blinkTimer -ge $t.blinkDelay) {
        $t.blinking = $true
        $t.blinkTimer = 0.0
    }

    # 帧推进（flashing 时冻结）
    if (-not $t.flashing -and $t.timer -ge $t.msPerFrame) {
        $last = 1
        if ($t.status -eq $STATUS_CRASHED -or $t.status -eq $STATUS_JUMPING) { $last = 0 }
        if ($t.currentFrame -eq $last) { $t.currentFrame = 0 } else { $t.currentFrame++ }
        $t.timer = 0.0
    }
}

function Start-Jump([double]$speed) {
    # trex.ts · startJump
    $t = $script:G.trex
    if (-not $t.jumping) {
        Update-TrexAnim 0.0 $STATUS_JUMPING
        $t.jumpVelocity    = $C.INITIAL_JUMP_VELOCITY - ($speed / 10.0)   # -10 - speed/10
        $t.jumping         = $true
        $t.reachedMinHeight = $false
        $t.speedDrop       = $false
    }
}

function End-Jump {
    # trex.ts · endJump：未达最小高度时「什么都不做」
    $t = $script:G.trex
    if ($t.reachedMinHeight -and $t.jumpVelocity -lt $C.DROP_VELOCITY) {
        $t.jumpVelocity = $C.DROP_VELOCITY
    }
}

function Set-SpeedDrop {
    # trex.ts · setSpeedDrop
    $t = $script:G.trex
    $t.speedDrop = $true
    $t.jumpVelocity = 1.0
}

function Set-Duck([bool]$isDucking) {
    # trex.ts · setDuck
    $t = $script:G.trex
    if ($isDucking -and $t.status -ne $STATUS_DUCKING) {
        Update-TrexAnim 0.0 $STATUS_DUCKING
        $t.ducking = $true
    } elseif ($t.status -eq $STATUS_DUCKING) {
        Update-TrexAnim 0.0 $STATUS_RUNNING
        $t.ducking = $false
    }
}

function Reset-Trex {
    # trex.ts · reset
    $t = $script:G.trex
    $t.xPos         = [double]$C.TREX_START_X
    $t.yPos         = [double]$C.GROUND_Y
    $t.jumpVelocity = 0.0
    $t.jumping      = $false
    $t.ducking      = $false
    Update-TrexAnim 0.0 $STATUS_RUNNING
    $t.speedDrop    = $false
    $t.jumpCount    = 0
    $script:G.jumpCount = $t.jumpCount
}

function Update-Jump([double]$deltaTime) {
    # trex.ts · updateJump —— 关键：Math.round 只包 jumpVelocity*framesElapsed
    $t = $script:G.trex
    $msPerFrame    = 1000.0 / 60.0
    $framesElapsed = $deltaTime / $msPerFrame

    if ($t.speedDrop) {
        $t.yPos += (Get-JsRound ($t.jumpVelocity * $C.SPEED_DROP_COEFFICIENT * $framesElapsed))
    } else {
        $t.yPos += (Get-JsRound ($t.jumpVelocity * $framesElapsed))
    }
    $t.jumpVelocity += $C.GRAVITY * $framesElapsed

    # 最小高度（绝对值 63）
    if ($t.yPos -lt $t.minJumpHeight -or $t.speedDrop) { $t.reachedMinHeight = $true }
    # 最大高度（⚠ 裸配置值 30）
    if ($t.yPos -lt $C.MAX_JUMP_HEIGHT -or $t.speedDrop) { End-Jump }

    # 落地
    if ($t.yPos -gt $C.GROUND_Y) {
        Reset-Trex
        $t.jumpCount++
        $script:G.jumpCount = $t.jumpCount
    }
}
#endregion

#region ── 障碍物（obstacle.ts / horizon.ts） ───────────────────────────────────
# 难度系数：原版间隔随速度线性增长，导致"越快越轻松"。
# 这里让间隔随速度收紧（速度 6 时不收，速度 20 时收到 0.58），翼龙再额外乘 0.6，
# 于是翼龙可以和仙人掌挨得很近出现，同时保证 35 帧滞空足够跳过（最紧仍有 ~400px）。
function Get-GapScale([double]$speed, [string]$typeName) {
    $f = 1.0 - ($speed - 6.0) * 0.030
    if ($f -lt 0.55) { $f = 0.55 }
    if ($typeName -eq 'pterodactyl') { $f = $f * 0.60 }
    return $f
}

function Get-Gap([double]$speed) {
    # obstacle.ts · getGap（注意：公式里没有画布宽度）
    $type = $script:GapType
    $minGap = Get-JsRound ($script:GapWidth * $speed + $type.minGap * $C.GAP_COEFFICIENT)
    $maxGap = Get-JsRound ($minGap * $C.MAX_GAP_COEFFICIENT)
    $g = Get-RandomNum $minGap $maxGap
    $f = Get-GapScale $speed $type.type
    $g2 = [int][Math]::Round($g * $f)
    if ($g2 -lt 90) { $g2 = 90 }        # 兜底：再紧也要留出可跳的余量
    return $g2
}

function New-Obstacle([hashtable]$type, [double]$speed, [int]$ForceSize = 0) {
    $o = @{}
    $o.id = $script:G.nextObstacleId
    $script:G.nextObstacleId = $script:G.nextObstacleId + 1
    $o.createSpeed = $speed
    $o.type = $type.type
    $o.typeConfig = $type
    if ($ForceSize -gt 0) { $o.size = $ForceSize }
    else { $o.size = Get-RandomNum 1 $C.MAX_OBSTACLE_LENGTH }   # {1,2,3} 均匀
    $o.xPos = [double]($script:G.canvasW + $type.width)   # 不是 width*size
    $o.yPos = 0.0
    $o.width = 0
    $o.gap = 0
    $o.speedOffset = 0.0
    $o.currentFrame = 0
    $o.timer = 0.0
    $o.remove = $false
    $o.followingObstacleCreated = $false

    # obstacle.ts · init
    if ($o.size -gt 1 -and $type.multipleSpeed -gt $speed) { $o.size = 1 }   # 速度不够 → 强制单体
    $o.width = $type.width * $o.size

    if ($type.yPos -is [array]) {
        $o.yPos = [double]$type.yPos[(Get-RandomNum 0 ($type.yPos.Count - 1))]
    } else {
        $o.yPos = [double]$type.yPos
    }

    # ── 大小仙人掌混排 ────────────────────────────────────────────────────────
    # 原版的多连体是同一张图横排，看着很单调。这里在速度够快（≥7，两种都能出现）时，
    # 让连体里的每个单元各自随机取大/小仙人掌；每个单元用自己那套完整碰撞盒，
    # 按它在组内的偏移平移 —— 所以判定与画面仍然一一对应。
    # （$ForceSize 是自检用的强制型号，此时不做混排，保证数值可预期。）
    $o.units = $null
    $mixable = ($ForceSize -eq 0) -and ($type.type -ne 'pterodactyl') -and
               ($speed -ge 7.0) -and ($o.size -gt 1)
    if ($mixable) {
        $units = @()
        $unitX = 0
        $maxH = 0
        $minY = 9999
        for ($i = 0; $i -lt $o.size; $i++) {
            $ut = $ObstacleTypes[(Get-RandomNum 0 1)]      # 0=小仙人掌 1=大仙人掌
            $units += @{ type = $ut; x = $unitX }
            $unitX += $ut.width
            if ($ut.height -gt $maxH) { $maxH = $ut.height }
            if ($ut.yPos -lt $minY) { $minY = $ut.yPos }
        }
        $o.units = $units
        $o.width = $unitX
        $o.yPos = [double]$minY                            # 高的那个决定外框顶部
        # 合成一个「等效类型」，让外框判定（width*size / height）保持自洽
        $o.typeConfig = @{
            type = $type.type; width = [int][Math]::Round($unitX / [double]$o.size)
            height = $maxH; yPos = $minY; minGap = $type.minGap
            multipleSpeed = $type.multipleSpeed; numFrames = 0; frameRate = 0.0
            speedOffset = 0.0; boxes = $type.boxes
        }
        $boxes = @()
        foreach ($u in $units) {
            foreach ($b in $u.type.boxes) {
                $boxes += , @(($b[0] + $u.x), $b[1], $b[2], $b[3])
            }
        }
        $o.boxes = $boxes
    } else {
        # 碰撞盒克隆
        $boxes = @()
        foreach ($b in $type.boxes) { $boxes += , @($b[0], $b[1], $b[2], $b[3]) }
        # obstacle.ts · init 的 size 改写
        if ($o.size -gt 1) {
            $boxes[1][2] = $o.width - $boxes[0][2] - $boxes[2][2]
            $boxes[2][0] = $o.width - $boxes[2][2]
        }
        $o.boxes = $boxes
    }

    if ($type.speedOffset -ne 0.0) {
        if ($script:Rng.NextDouble() -gt 0.5) { $o.speedOffset = [double]$type.speedOffset }
        else                                  { $o.speedOffset = [double](-$type.speedOffset) }
    }

    $script:GapType  = $type
    $script:GapWidth = $o.width
    $o.gap = Get-Gap $speed
    return $o
}

function Add-NewObstacle([double]$speed) {
    # horizon.ts · addNewObstacle：默认玩法 obstacleCount = 3-1 = 2 → 索引 0..2
    $count = $ObstacleTypes.Count - 1        # 2
    while ($true) {
        $idx = Get-RandomNum 0 $count
        $type = $ObstacleTypes[$idx]
        # 翼龙只在第三幕「繁星夜」及其之后出场（用户要求：别在第一/二幕冒出来）
        if ((Test-DuplicateObstacle $type.type) -or ($speed -lt $type.minSpeed) -or
            (($type.type -eq 'pterodactyl') -and ($script:Phase -lt 2))) {
            continue                          # 递归重选
        }
        $o = New-Obstacle $type $speed
        $script:G.obstacles = @($script:G.obstacles) + @($o)
        $script:G.obstacleHistory = @($type.type) + $script:G.obstacleHistory
        if ($script:G.obstacleHistory.Count -gt 1) {
            $keep = $C.MAX_OBSTACLE_DUPLICATION
            if ($script:G.obstacleHistory.Count -gt $keep) {
                $script:G.obstacleHistory = @($script:G.obstacleHistory[0..($keep - 1)])
            }
        }
        return
    }
}

function Test-DuplicateObstacle([string]$nextType) {
    # horizon.ts · duplicateObstacleCheck：数「前缀连续相同」个数
    $dup = 0
    foreach ($h in $script:G.obstacleHistory) {
        if ($h -eq $nextType) { $dup++ } else { $dup = 0 }
    }
    return ($dup -ge $C.MAX_OBSTACLE_DUPLICATION)
}

function Update-Obstacle([hashtable]$o, [double]$deltaTime, [double]$speed) {
    if ($o.remove) { return }
    $s = $speed
    if ($o.typeConfig.speedOffset -ne 0.0) { $s += $o.speedOffset }
    # obstacle.ts · update：Math.floor(speed * FPS/1000 * deltaTime)
    $o.xPos -= [Math]::Floor($s * ($C.FPS / 1000.0) * $deltaTime)
    if ($o.typeConfig.numFrames -gt 0) {
        $o.timer += $deltaTime
        if ($o.timer -ge $o.typeConfig.frameRate) {
            if ($o.currentFrame -eq $o.typeConfig.numFrames - 1) { $o.currentFrame = 0 }
            else { $o.currentFrame++ }
            $o.timer = 0.0
        }
    }
    if (-not (($o.xPos + $o.width) -gt 0)) { $o.remove = $true }   # isVisible()
}

function Update-Horizon([double]$deltaTime, [double]$speed) {
    # horizon.ts · updateObstacles（含原版的 shift() 怪癖，照抄）
    $updated = @()
    foreach ($o in $script:G.obstacles) { $updated += $o }

    foreach ($o in $script:G.obstacles) {
        Update-Obstacle $o $deltaTime $speed
        if ($o.remove) {
            if ($updated.Count -le 1) { $updated = @() }
            else { $updated = @($updated[1..($updated.Count - 1)]) }   # shift()
        }
    }
    $script:G.obstacles = $updated

    if ($script:G.obstacles.Count -gt 0) {
        $last = $script:G.obstacles[$script:G.obstacles.Count - 1]
        $visible = ($last.xPos + $last.width) -gt 0
        if ((-not $last.followingObstacleCreated) -and $visible -and
            (($last.xPos + $last.width + $last.gap) -lt $script:G.canvasW)) {
            Add-NewObstacle $speed
            $last.followingObstacleCreated = $true
        }
    } else {
        Add-NewObstacle $speed
    }
}
#endregion

#region ── 碰撞检测（offline.ts · checkForCollision） ───────────────────────────
function Test-BoxCompare([int]$ax, [int]$ay, [int]$aw, [int]$ah,
                         [int]$bx, [int]$by, [int]$bw, [int]$bh) {
    if (($ax -lt ($bx + $bw)) -and (($ax + $aw) -gt $bx) -and
        ($ay -lt ($by + $bh)) -and (($ah + $ay) -gt $by)) { return $true }
    return $false
}

function Test-Collision([hashtable]$o) {
    $t = $script:G.trex
    # 外层盒：+1 / -2 白边修正；⚠ 下蹲时仍用 config.width = 44
    $tX = [int]($t.xPos + 1); $tY = [int]($t.yPos + 1)
    $tW = $C.TREX_WIDTH - 2;  $tH = $C.TREX_HEIGHT - 2

    $oX = [int]($o.xPos + 1); $oY = [int]($o.yPos + 1)
    $oW = [int]($o.typeConfig.width * $o.size - 2)
    $oH = [int]($o.typeConfig.height - 2)

    if (-not (Test-BoxCompare $tX $tY $tW $tH $oX $oY $oW $oH)) { return $false }

    if ($t.ducking) { $tBoxes = $TrexBoxesDucking } else { $tBoxes = $TrexBoxesRunning }
    foreach ($tb in $tBoxes) {
        $adjTX = $tb[0] + $tX; $adjTY = $tb[1] + $tY
        foreach ($ob in $o.boxes) {
            $adjOX = $ob[0] + $oX; $adjOY = $ob[1] + $oY
            if (Test-BoxCompare $adjTX $adjTY $tb[2] $tb[3] $adjOX $adjOY $ob[2] $ob[3]) {
                return $true
            }
        }
    }
    return $false
}
#endregion

#region ── 分数（distance_meter.ts） ───────────────────────────────────────────
function Get-ActualDistance([double]$distance) {
    # distance_meter.ts · getActualDistance
    # 规格 §6.2 / §18.9：score = Math.round( Math.ceil(distanceRan) * 0.025 )，ceil 不能漏
    if ($distance -eq 0) { return 0 }
    return (Get-JsRound ([Math]::Ceiling($distance) * $C.SCORE_COEFFICIENT))
}

function Set-HighScore([double]$distance) {
    $d = Get-ActualDistance $distance
    $str = ([string]$d).PadLeft($script:G.meter.maxScoreUnits, '0')
    $script:G.meter.highScoreStr = 'HI ' + $str
}

function Update-DistanceMeter([double]$deltaTime, [double]$distanceRan) {
    # distance_meter.ts · update：返回是否触发成就闪烁
    $m = $script:G.meter
    $playSound = $false
    if (-not $m.achievement) {
        $distance = Get-ActualDistance $distanceRan
        $m.score = $distance
        if ($distance -gt $m.maxScore -and $m.maxScoreUnits -eq $C.MAX_DISTANCE_UNITS) {
            $m.maxScoreUnits++
            $m.maxScore = [int]([string]$m.maxScore + '9')
        }
        if ($distance -gt 0) {
            if (($distance % $C.ACHIEVEMENT_DISTANCE) -eq 0) {
                $m.achievement = $true
                $m.flashTimer = 0.0
                $playSound = $true
            }
            $m.digits = (([string]$distance).PadLeft($m.maxScoreUnits, '0')).ToCharArray()
        } else {
            $m.digits = ('0' * $m.maxScoreUnits).ToCharArray()
        }
    } else {
        if ($m.flashIterations -le $C.FLASH_ITERATIONS) {
            $m.flashTimer += $deltaTime
            if ($m.flashTimer -gt ($C.FLASH_DURATION * 2)) {
                $m.flashTimer = 0.0
                $m.flashIterations++
            }
        } else {
            $m.achievement = $false
            $m.flashIterations = 0
            $m.flashTimer = 0.0
        }
        # 闪烁期间显示层冻结：分数照常累加，但 digits 不刷新
        $m.score = Get-ActualDistance $distanceRan
    }
    return $playSound
}
#endregion

#region ── 单帧逻辑（offline.ts · Runner.update） ──────────────────────────────
function Step-Frame([double]$deltaTime) {
    $g = $script:G
    $t = $g.trex

    if (-not $g.playing) {
        # 未激活：只眨眼
        Update-TrexAnim $deltaTime
        return
    }

    # (C) 跳跃物理
    if ($t.jumping) { Update-Jump $deltaTime }

    # (D) 起跑保护
    $g.runningTime += $deltaTime
    $hasObstacles = $g.runningTime -gt $C.CLEAR_TIME

    # (D2) 天空/天气（纯装饰）
    Update-Sky $deltaTime

    # (F) 世界滚动（障碍移动/生成用「增长前」的速度）
    #     原版：只有 hasObstacles（runningTime > clearTime）时才更新障碍，开局 3 秒无干扰
    if ((-not $g.crashed) -and $hasObstacles) {
        Update-Horizon $deltaTime $g.currentSpeed
    }

    # (G) 碰撞（只测第一个障碍）
    $collision = $false
    if ($hasObstacles -and $g.obstacles.Count -gt 0) {
        $collision = Test-Collision $g.obstacles[0]
    }

    # (J) 距离与速度
    if (-not $collision) {
        $g.distanceRan += $g.currentSpeed * $deltaTime / $C.MS_PER_FRAME
        if ($g.currentSpeed -lt $C.MAX_SPEED) { $g.currentSpeed += $C.ACCELERATION }
    } else {
        # gameOver()
        $g.crashed = $true
        $g.playing = $false
        $g.meter.achievement = $false
        # 规格 §14.6：gameOver 里是 tRex.update(100, CRASHED)
        Update-TrexAnim 100 $STATUS_CRASHED
        # 规格 §6.5：highestScore 存的是 Math.ceil(distanceRan)（像素距离），不是分数
        if ($g.distanceRan -gt $g.highestScore) {
            $g.highestScore = [Math]::Ceiling($g.distanceRan)
            Set-HighScore ([Math]::Ceiling($g.distanceRan))
        }
    }

    # (K) 分数
    [void](Update-DistanceMeter $deltaTime $g.distanceRan)

    # (M) 尾帧
    Update-TrexAnim $deltaTime

    # speedDrop 落地且恰好在地面 → 自动转下蹲
    if ($t.speedDrop -and $t.yPos -eq $C.GROUND_Y) {
        $t.speedDrop = $false
        Set-Duck $true
    }
}
#endregion

#region ── 位图（画面可与原版不同，位置与尺寸对齐原版） ─────────────────────────
$BM_DINO_A = @(
    '........#####..'
    '........######.'
    '........#.####.'
    '........######.'
    '........#####..'
    '........####...'
    '.......#####...'
    '......######...'
    '###########....'
    '.##########....'
    '.#########.....'
    '.########......'
    '.##...###......'
    '.##............'
    '.##............'
    '.##............'
)
$BM_DINO_B = @(
    '........#####..'
    '........######.'
    '........#.####.'
    '........######.'
    '........#####..'
    '........####...'
    '.......#####...'
    '......######...'
    '###########....'
    '.##########....'
    '.#########.....'
    '.########......'
    '.##...###......'
    '.......###.....'
    '.......###.....'
    '.......###.....'
)
# 眨眼帧：眼睛那格（第 3 行 col 9）由缺口变成实心 → 看起来闭上了
$BM_DINO_A_BLINK = @(
    '........#####..'
    '........######.'
    '........######.'
    '........######.'
    '........#####..'
    '........####...'
    '.......#####...'
    '......######...'
    '###########....'
    '.##########....'
    '.#########.....'
    '.########......'
    '.##...###......'
    '.##............'
    '.##............'
    '.##............'
)
$BM_DINO_B_BLINK = @(
    '........#####..'
    '........######.'
    '........######.'
    '........######.'
    '........#####..'
    '........####...'
    '.......#####...'
    '......######...'
    '###########....'
    '.##########....'
    '.#########.....'
    '.########......'
    '.##...###......'
    '.......###.....'
    '.......###.....'
    '.......###.....'
)
$BM_DINO_JUMP = @(
    '........#####..'
    '........######.'
    '........#.####.'
    '........######.'
    '........#####..'
    '........####...'
    '.......#####...'
    '......######...'
    '###########....'
    '.##########....'
    '.#########.....'
    '.########......'
    '.##...###......'
    '.##...###......'
    '.##...###......'
    '.##...###......'
)
$BM_DINO_CRASH = @(
    '........#####..'
    '........######.'
    '........#..###.'
    '........######.'
    '........#####..'
    '........####...'
    '.......#####...'
    '......######...'
    '###########....'
    '.##########....'
    '.#########.....'
    '.########......'
    '.##...###......'
    '.##...###......'
    '.##...###......'
    '.##...###......'
)
$BM_DINO_DUCK = @(
    '.........##########.'
    '.........##########.'
    '####################'
    '####################'
    '####################'
    '.###...####...####..'
    '.##.....##.....##...'
    '.#.......#......#...'
    '....................'
)
$BM_CACTUS_S = @(
    '..#...'
    '..#...'
    '#.#...'
    '#.#...'
    '###...'
    '..#...'
    '..#.#.'
    '..#.#.'
    '..###.'
    '..#...'
    '..#...'
    '..#...'
)
$BM_CACTUS_S2 = @(
    '..#...'
    '..#...'
    '..#...'
    '#.#...'
    '#.#...'
    '###...'
    '..#.#.'
    '..###.'
    '..#...'
    '..#...'
    '..#...'
    '..#...'
)
$BM_CACTUS_L = @(
    '...###...'
    '...###...'
    '...###...'
    '##.###...'
    '##.###...'
    '##.###.##'
    '##.###.##'
    '#######..'
    '...###.##'
    '...######'
    '...###...'
    '...###...'
    '...###...'
    '...###...'
    '...###...'
    '...###...'
    '...###...'
)
$BM_CACTUS_L2 = @(
    '...###...'
    '...###...'
    '...###...'
    '...###.##'
    '...###.##'
    '...###.##'
    '...######'
    '##.###...'
    '##.###...'
    '##.###...'
    '#######..'
    '...###...'
    '...###...'
    '...###...'
    '...###...'
    '...###...'
    '...###...'
)
$BM_PTERO_A = @(
    '..#..........#..'
    '..##........##..'
    '..###......###..'
    '..####....####..'
    '...####..####...'
    '....########....'
    '.....######.....'
    '......####......'
    '......####......'
    '.......##.......'
    '.......##.......'
    '......#..#......'
    '......#..#......'
    '................'
)
$BM_PTERO_B = @(
    '................'
    '................'
    '.....######.....'
    '....########....'
    '...####..####...'
    '..###......###..'
    '..##........##..'
    '..#..........#..'
    '......####......'
    '.......##.......'
    '.......##.......'
    '......#..#......'
    '......#..#......'
    '................'
)
# 弯月（8x8 点）：点阵是「加法」缓冲没法挖洞，所以直接画成 C 形
$BM_MOON = @(
    '..####..'
    '.####...'
    '####....'
    '###.....'
    '###.....'
    '####....'
    '.####...'
    '..####..'
)
#endregion

#region ── 天空 / 天气（纯装饰，不影响物理） ────────────────────────────────────
# 三幕循环：0 = 白天（稀云、少星） → 1 = 天亮（颜色反转：浅底深字） → 2 = 夜晚（繁星 + 弯月 + 流星）
$script:Phase        = 0
$script:PhaseChanged = $true
$script:PhaseLength  = 30000.0    # 每幕持续的世界距离（像素）—— 已按 2.5 倍延长
$script:SkyTimer     = 0.0
$script:Stars        = @()
$script:Clouds       = @()
$script:Shooting     = $null

function Initialize-Sky {
    $script:Stars = @()
    $script:Clouds = @()
    for ($i = 0; $i -lt 44; $i++) {
        $script:Stars += @{
            x  = $script:Rng.NextDouble() * 900.0
            y  = 5.0 + $script:Rng.NextDouble() * 66.0
            ph = $script:Rng.NextDouble() * 1600.0
        }
    }
    for ($i = 0; $i -lt 4; $i++) {
        $script:Clouds += @{
            x = $script:Rng.NextDouble() * 900.0
            y = 12.0 + $script:Rng.NextDouble() * 36.0
        }
    }
    $script:Shooting = $null
    $script:Phase = 0
    $script:PhaseChanged = $true
    $script:SkyTimer = 0.0
}

function Update-Sky([double]$deltaTime) {
    $g = $script:G
    $idx = [int][Math]::Floor($g.distanceRan / $script:PhaseLength) % 3
    if ($idx -ne $script:Phase) {
        $script:Phase = $idx
        $script:PhaseChanged = $true
    }
    $script:SkyTimer += $deltaTime
    $dx = $g.currentSpeed * 0.12 * ($deltaTime / 16.6667)
    foreach ($c in $script:Clouds) {
        $c.x -= $dx
        if ($c.x -lt -40.0) { $c.x = $g.canvasW + 20.0 }
    }
    foreach ($s in $script:Stars) {
        $s.x -= $dx * 0.3
        if ($s.x -lt -6.0) { $s.x = $g.canvasW + 6.0 }
    }
    if ($script:Phase -eq 2) {
        if ($null -eq $script:Shooting) {
            if ($script:Rng.NextDouble() -lt 0.0022) {
                $script:Shooting = @{
                    x    = $g.canvasW * 0.45 + $script:Rng.NextDouble() * ($g.canvasW * 0.45)
                    y    = 30.0 + $script:Rng.NextDouble() * 22.0
                    life = 80
                }
            }
        } else {
            $script:Shooting.x -= 9.0
            $script:Shooting.y += 2.0
            $script:Shooting.life--
            if ($script:Shooting.life -le 0) { $script:Shooting = $null }
        }
    } else {
        $script:Shooting = $null
    }
}

function Draw-Sky {
    # 幕次：0 = 夜晚·稀云少星（暗底） → 1 = 天亮（颜色反转，浅底深字） → 2 = 夜晚·满天繁星 + 弯月 + 流星
    $ph = $script:Phase
    $limit = 6                                    # 第一幕：夜晚但星少
    if ($ph -eq 1) { $limit = 9 }                 # 天亮：略多
    elseif ($ph -eq 2) { $limit = 44 }            # 第三幕：满天繁星（闪烁）
    $i = 0
    foreach ($s in $script:Stars) {
        if ($i -ge $limit) { break }
        $on = $true
        if ($ph -eq 2) { $on = ((($script:SkyTimer + $s.ph) % 1600.0) -lt 1050.0) }
        if ($on) { Fill-PxRect ([int]$s.x) ([int]$s.y) $PX_PER_DOT_X $PX_PER_DOT_Y }
        $i++
    }
    # 稀云：只有前两幕有（第一幕的"稀云"、天亮时的残云）；满天繁星那幕没有云
    if ($ph -ne 2) {
        foreach ($c in $script:Clouds) {
            $cx = [int]$c.x; $cy = [int]$c.y
            Fill-PxRect $cx $cy 21 3
            Fill-PxRect ($cx + 6) ($cy - 3) 12 3
            Fill-PxRect ($cx + 3) ($cy + 3) 9 3
        }
    }
    # 弯月：只有「满天繁星」那一幕
    if ($ph -eq 2) {
        $mx = [int]($script:G.canvasW - 96)
        if ($mx -lt 0) { $mx = 0 }
        Draw-Bitmap $BM_MOON $mx 12
    }
    # 流星：亮点头部 + 逐渐变稀的斜向尾迹（原来等间距 7 个点，看着像掉木棍）
    if ($null -ne $script:Shooting) {
        $sx = [int]$script:Shooting.x
        $sy = [int]$script:Shooting.y
        Fill-PxRect $sx $sy ($PX_PER_DOT_X * 2) ($PX_PER_DOT_Y * 2)          # 头部（2x2 点，最亮）
        for ($k = 1; $k -le 14; $k++) {
            if (($k -gt 5) -and (($k % 2) -eq 0)) { continue }               # 尾巴越远越稀
            $tx = [int]($sx + $k * 2.6)
            $ty = [int]($sy - $k * 1.9)
            if ($tx -lt 0 -or $ty -lt 0) { continue }
            Fill-PxRect $tx $ty $PX_PER_DOT_X $PX_PER_DOT_Y
        }
    }
}
#endregion

#region ── 终端渲染 ───────────────────────────────────────────────────────────
# 渲染采用「按列区间的脏矩形」策略：整行重绘（100 列 x 25 行）在 PowerShell 里要 10ms+
# 一帧只有恐龙/障碍/地面那几列在动，所以每帧只重组被改动的列区间。
$script:Cols      = 150          # 点列数
$script:SubRows   = 38           # 点行数
$script:CharCols  = 75           # 字符列数 (Cols / DOTS_PER_CHAR_X)
$script:FieldRows = 10           # 字符行数 (SubRows / DOTS_PER_CHAR_Y)
$script:RenderMode = 'braille'   # braille | block | ascii
# 盲文点阵位映射：点号 1..8 对应位 0..7，排列为
#   1 4     (0x01) (0x08)
#   2 5     (0x02) (0x10)
#   3 6     (0x04) (0x20)
#   7 8     (0x40) (0x80)
$script:BrailleBit = @(
    @(0x01, 0x02, 0x04, 0x40),
    @(0x08, 0x10, 0x20, 0x80)
)
$script:Sub       = $null        # 点阵缓冲（SubRows x Cols）
$script:DirtyMin  = $null        # 本帧每个字符行被改动的列范围
$script:DirtyMax  = $null
$script:PrevMin   = $null        # 上一帧的列范围（离开的图形需要再擦一次）
$script:PrevMax   = $null
$script:Rows      = $null        # 本帧期望的字符行内容
$script:Screen    = $null        # 屏幕上当前显示的内容
$script:OverlayRows = $null      # 上一帧被 GAME OVER 覆盖的行
$script:TermRows  = 0
$script:TermCols  = 0
$script:Headless  = $false
$script:UseAscii  = $false
$script:RenderFail = 0      # 连续写屏失败计数（stdout 被重定向时用来自救）
$script:PrevStatus = ''
$script:GlyphUp    = $true  # 终端能否显示 ▀（GBK 代码页里没有它！）
$script:GlyphDown  = $true  # 能否显示 ▄
$script:GlyphFull  = $true  # 能否显示 █
$script:NeedFullRepaint = $false
$script:FirstPaint = $true  # 开局第一帧不走过渡，直接定色
$script:CurBg      = 'Black'
$script:FadeFrom   = 'Black'
$script:FadeTo     = 'Black'
$script:RowState   = @()    # 每个终端行的过渡状态：0=旧色 1=中间灰 2=目标色
$script:RowTimer   = @()
$script:CurtainRow = -1
$script:CurtainClock = 0.0

# 每行当前该用什么底色；前景按底色取对比色（避免灰底灰字看不见）
# 四层过渡（自下而上依次扫过，顺序固定不可乱）：
#   去白：L1 灰底黑点 → L2 纯灰 → L3 白底黑点 → L4 纯白
#   去黑：L1 灰底白点 → L2 纯灰 → L3 黑底白点 → L4 纯黑
function Get-RowBg([int]$r) {
    $st = 4
    if (($r -ge 0) -and ($r -lt $script:RowState.Count)) { $st = $script:RowState[$r] }
    if ($st -eq 0) { return $script:FadeFrom }                 # 还没扫到：旧色
    if (($st -eq 1) -or ($st -eq 2)) { return 'Gray' }          # L1/L2 = 灰底
    return $script:FadeTo                                       # L3/L4 = 目标底色
}
function Get-RowFg([int]$r) {
    $st = 4
    if (($r -ge 0) -and ($r -lt $script:RowState.Count)) { $st = $script:RowState[$r] }
    if ($st -eq 0) { return (Get-ContrastFg $script:FadeFrom) }
    if ($st -eq 2) { return 'Black' }                           # L2 纯灰：点色=灰 → 看不出点
    if (($st -eq 1) -or ($st -eq 3)) { return $script:DotFg }   # L1/L3 点层
    return (Get-ContrastFg $script:FadeTo)                      # L4 纯目标色
}
function Test-RowDots([int]$st) { return (($st -eq 1) -or ($st -eq 3)) }
function Get-ContrastFg([string]$bg) {
    if (($bg -eq 'White') -or ($bg -eq 'Gray')) { return 'Black' }
    return 'Gray'
}
# 游戏区之外的行：整行铺底色；点层铺点阵，其余铺空格
function Write-RowFill([int]$r) {
    if ($script:Headless) { return }
    try {
        $bg = Get-RowBg $r
        [Console]::BackgroundColor = [ConsoleColor]$bg
        [Console]::ForegroundColor = [ConsoleColor](Get-RowFg $r)
        [Console]::SetCursorPosition(0, $r)
        $st = 4
        if (($r -ge 0) -and ($r -lt $script:RowState.Count)) { $st = $script:RowState[$r] }
        if (Test-RowDots $st) {
            [Console]::Write((('⠂' + '⠄') * [int]($script:TermCols / 2)))
        } else {
            [Console]::Write(' ' * $script:TermCols)
        }
    } catch { }
}

function Initialize-Terminal {
    try {
        $script:TermCols = [Console]::WindowWidth
        $script:TermRows = [Console]::WindowHeight
    } catch {
        $script:TermCols = 100
        $script:TermRows = 30
    }
    if ($script:TermCols -lt 20) { $script:TermCols = 100 }
    if ($script:TermRows -lt 10) { $script:TermRows = 30 }
    Initialize-RowStates
}

# 每个终端行的过渡状态（换幕幕布用）：0=旧色 1=点层 2=灰层 3=目标色
function Initialize-RowStates {
    $script:RowState = [int[]]::new($script:TermRows)
    $script:RowTimer = [double[]]::new($script:TermRows)
    # 初始必须是"目标色"(3)：写 2 会停在灰层，开局整屏发白
    for ($i = 0; $i -lt $script:TermRows; $i++) { $script:RowState[$i] = 3; $script:RowTimer[$i] = 0.0 }
    $script:CurtainRow = -1
}

function Initialize-Buffers([int]$canvasW) {
    $script:Cols = [int][Math]::Ceiling($canvasW / [double]$PX_PER_DOT_X)              # 点列数
    $script:SubRows = [int][Math]::Ceiling($C.CANVAS_HEIGHT / [double]$PX_PER_DOT_Y)   # 点行数
    $script:CharCols = [int][Math]::Ceiling($script:Cols / [double]$DOTS_PER_CHAR_X)   # 字符列数
    $script:FieldRows = [int][Math]::Ceiling($script:SubRows / [double]$DOTS_PER_CHAR_Y)
    $script:Sub = [bool[]]::new($script:SubRows * $script:Cols)
    $script:DirtyMin = [int[]]::new($script:FieldRows)
    $script:DirtyMax = [int[]]::new($script:FieldRows)
    $script:PrevMin  = [int[]]::new($script:FieldRows)
    $script:PrevMax  = [int[]]::new($script:FieldRows)
    $script:Rows   = [string[]]::new($script:FieldRows)
    $script:Screen = [string[]]::new($script:FieldRows)
    $script:OverlayRows = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $script:FieldRows; $i++) {
        $script:Rows[$i] = ''
        $script:Screen[$i] = ''
        $script:DirtyMin[$i] = [int]::MaxValue
        $script:DirtyMax[$i] = -1
        $script:PrevMin[$i] = [int]::MaxValue
        $script:PrevMax[$i] = -1
    }
}

# 入参是「点列」区间，内部换算成字符列区间（DOTS_PER_CHAR_X = 2，故右移 1 位）
function Mark-Dirty([int]$row, [int]$dc0, [int]$dc1) {
    if ($row -lt 0 -or $row -ge $script:FieldRows) { return }
    $c0 = $dc0 -shr 1
    $c1 = $dc1 -shr 1
    if ($c0 -lt 0) { $c0 = 0 }
    if ($c1 -ge $script:CharCols) { $c1 = $script:CharCols - 1 }
    if ($c1 -lt $c0) { return }
    if ($c0 -lt $script:DirtyMin[$row]) { $script:DirtyMin[$row] = $c0 }
    if ($c1 -gt $script:DirtyMax[$row]) { $script:DirtyMax[$row] = $c1 }
}

# 在逻辑像素空间填一个矩形（热路径：全部内联，避免 PowerShell 函数调用开销）
function Fill-PxRect([int]$x, [int]$y, [int]$w, [int]$h) {
    $cols = $script:Cols; $rows = $script:SubRows; $sub = $script:Sub
    $c0 = [int][Math]::Floor($x / [double]$PX_PER_DOT_X); $c1 = [int][Math]::Floor(($x + $w - 1) / [double]$PX_PER_DOT_X)
    $r0 = [int][Math]::Floor($y / [double]$PX_PER_DOT_Y); $r1 = [int][Math]::Floor(($y + $h - 1) / [double]$PX_PER_DOT_Y)
    if ($c0 -lt 0) { $c0 = 0 }
    if ($c1 -ge $cols) { $c1 = $cols - 1 }
    if ($r0 -lt 0) { $r0 = 0 }
    if ($r1 -ge $rows) { $r1 = $rows - 1 }
    for ($r = $r0; $r -le $r1; $r++) {
        $base = $r * $cols
        for ($c = $c0; $c -le $c1; $c++) { $sub[$base + $c] = $true }
        Mark-Dirty ($r -shr 2) $c0 $c1        # 4 个点 = 1 个字符行
    }
}

# 位图里每个 '#' = 一个点（4x4 逻辑像素）
function Draw-Bitmap($lines, [int]$x, [int]$y) {
    $cols = $script:Cols; $rows = $script:SubRows; $sub = $script:Sub
    $dMin = $script:DirtyMin; $dMax = $script:DirtyMax
    $rowCount = $lines.Count
    $xBase = [int][Math]::Floor($x / [double]$PX_PER_DOT_X)
    $yBase = [int][Math]::Floor($y / [double]$PX_PER_DOT_Y)
    for ($r = 0; $r -lt $rowCount; $r++) {
        $dr = $yBase + $r
        if ($dr -lt 0 -or $dr -ge $rows) { continue }
        $base = $dr * $cols
        $cr = $dr -shr 2
        $line = $lines[$r]
        $len = $line.Length
        $cMin = [int]::MaxValue; $cMax = -1
        for ($c = 0; $c -lt $len; $c++) {
            if ($line[$c] -ne '#') { continue }
            $dc = $xBase + $c
            if ($dc -lt 0 -or $dc -ge $cols) { continue }
            $sub[$base + $dc] = $true
            if ($dc -lt $cMin) { $cMin = $dc }
            if ($dc -gt $cMax) { $cMax = $dc }
        }
        if ($cMax -ge 0) {
            $cc0 = $cMin -shr 1
            $cc1 = $cMax -shr 1
            if ($cc0 -lt $dMin[$cr]) { $dMin[$cr] = $cc0 }
            if ($cc1 -gt $dMax[$cr]) { $dMax[$cr] = $cc1 }
        }
    }
}

function Draw-World {
    $g = $script:G
    $t = $g.trex

    Draw-Sky

    # 地面：恐龙/仙人掌/翼龙的底边都在 y=140，所以地平线放在点行 35（y=140..143）。
    # 之前铺了一条 12px 厚的实心带（那是原版 horizon sprite 的区域，实际只在顶部几像素
    # 画了线），结果把恐龙的腿整段吞掉、看起来像方块在平移 —— 改成细线，让精灵站在线上。
    $groundRow = [int][Math]::Floor(140 / [double]$PX_PER_DOT_Y)
    if ($groundRow -ge $script:SubRows) { $groundRow = $script:SubRows - 1 }
    $scroll = [int]($g.distanceRan)
    $base = $groundRow * $script:Cols
    for ($c = 0; $c -lt $script:Cols; $c++) { $script:Sub[$base + $c] = $true }
    Mark-Dirty ($groundRow -shr 2) 0 ($script:Cols - 1)
    # 滚动的小起伏：偶尔在线上方点一格，做出「地面在动」的观感
    $bumpRow = $groundRow - 1
    if (($bumpRow -ge 0) -and ((([int]($scroll / 7)) % 3) -eq 0)) {
        $start = (7 - ($scroll % 7)) % 7
        $base2 = $bumpRow * $script:Cols
        for ($c = $start; $c -lt $script:Cols; $c += 7) { $script:Sub[$base2 + $c] = $true }
        Mark-Dirty ($bumpRow -shr 2) 0 ($script:Cols - 1)
    }

    # 障碍
    foreach ($o in $g.obstacles) {
        $ox = [int][Math]::Round($o.xPos)
        $oy = [int][Math]::Round($o.yPos)
        switch ($o.type) {
            'cactusSmall' {
                if ($null -ne $o.units) {
                    foreach ($u in $o.units) {
                        if ($u.type.type -eq 'cactusLarge') { Draw-Bitmap $BM_CACTUS_L  ($ox + $u.x) $u.type.yPos }
                        else                               { Draw-Bitmap $BM_CACTUS_S  ($ox + $u.x) $u.type.yPos }
                    }
                } else {
                    for ($i = 0; $i -lt $o.size; $i++) {
                        if (($i % 2) -eq 0) { Draw-Bitmap $BM_CACTUS_S  ($ox + $i * 17) $oy }
                        else                { Draw-Bitmap $BM_CACTUS_S2 ($ox + $i * 17) $oy }
                    }
                }
            }
            'cactusLarge' {
                if ($null -ne $o.units) {
                    foreach ($u in $o.units) {
                        if ($u.type.type -eq 'cactusSmall') { Draw-Bitmap $BM_CACTUS_S  ($ox + $u.x) $u.type.yPos }
                        else                               { Draw-Bitmap $BM_CACTUS_L2 ($ox + $u.x) $u.type.yPos }
                    }
                } else {
                    for ($i = 0; $i -lt $o.size; $i++) {
                        if (($i % 2) -eq 0) { Draw-Bitmap $BM_CACTUS_L  ($ox + $i * 25) $oy }
                        else                { Draw-Bitmap $BM_CACTUS_L2 ($ox + $i * 25) $oy }
                    }
                }
            }
            'pterodactyl' {
                if ($o.currentFrame -eq 0) { Draw-Bitmap $BM_PTERO_A $ox $oy }
                else                       { Draw-Bitmap $BM_PTERO_B $ox $oy }
            }
        }
    }

    # T-Rex
    $tx = [int][Math]::Round($t.xPos)
    $ty = [int][Math]::Round($t.yPos)
    if ($t.ducking -and $t.status -ne $STATUS_CRASHED) {
        Draw-Bitmap $BM_DINO_DUCK $tx ($ty + 22)          # 下蹲图贴在 47px 盒底部
    } elseif ($t.status -eq $STATUS_CRASHED) {
        Draw-Bitmap $BM_DINO_CRASH $tx $ty
    } elseif ($t.jumping) {
        Draw-Bitmap $BM_DINO_JUMP $tx $ty
    } elseif ($t.status -eq $STATUS_DUCKING) {
        Draw-Bitmap $BM_DINO_DUCK $tx ($ty + 22)
    } else {
        if ($t.currentFrame -eq 0) {
            if ($t.blinking) { Draw-Bitmap $BM_DINO_A_BLINK $tx $ty }
            else             { Draw-Bitmap $BM_DINO_A $tx $ty }
        } else {
            if ($t.blinking) { Draw-Bitmap $BM_DINO_B_BLINK $tx $ty }
            else             { Draw-Bitmap $BM_DINO_B $tx $ty }
        }
    }
}

function Compose-Slice([int]$r, [int]$c0, [int]$c1) {
    # 把第 r 个字符行、字符列 c0..c1 的点阵打包成字符
    $cols = $script:Cols
    $sub = $script:Sub
    $mode = $script:RenderMode
    $bits = $script:BrailleBit
    $dTop = $r * $DOTS_PER_CHAR_Y
    $base0 = $dTop * $cols
    $base1 = ($dTop + 1) * $cols
    $base2 = ($dTop + 2) * $cols
    $base3 = ($dTop + 3) * $cols
    $has1 = ($dTop + 1) -lt $script:SubRows
    $has2 = ($dTop + 2) -lt $script:SubRows
    $has3 = ($dTop + 3) -lt $script:SubRows
    $n = $c1 - $c0 + 1
    $chars = [char[]]::new($n)
    for ($i = 0; $i -lt $n; $i++) {
        $dl = ($c0 + $i) * $DOTS_PER_CHAR_X
        $dr = $dl + 1
        $inL = $dl -lt $cols
        $inR = $dr -lt $cols
        if ($mode -eq 'braille') {
            $mask = 0
            if ($inL) {
                if ($sub[$base0 + $dl]) { $mask = $mask -bor $bits[0][0] }
                if ($has1 -and $sub[$base1 + $dl]) { $mask = $mask -bor $bits[0][1] }
                if ($has2 -and $sub[$base2 + $dl]) { $mask = $mask -bor $bits[0][2] }
                if ($has3 -and $sub[$base3 + $dl]) { $mask = $mask -bor $bits[0][3] }
            }
            if ($inR) {
                if ($sub[$base0 + $dr]) { $mask = $mask -bor $bits[1][0] }
                if ($has1 -and $sub[$base1 + $dr]) { $mask = $mask -bor $bits[1][1] }
                if ($has2 -and $sub[$base2 + $dr]) { $mask = $mask -bor $bits[1][2] }
                if ($has3 -and $sub[$base3 + $dr]) { $mask = $mask -bor $bits[1][3] }
            }
            if ($mask -eq 0) { $chars[$i] = $CH_SPACE }
            else { $chars[$i] = [char](0x2800 + $mask) }
        } else {
            # block / ascii：把 2x4 个点降采样成上、下半格
            $upOn = $false; $loOn = $false
            if ($inL -and $sub[$base0 + $dl]) { $upOn = $true }
            if (-not $upOn -and $has1) { if ($inL -and $sub[$base1 + $dl]) { $upOn = $true } }
            if (-not $upOn -and $inR -and $sub[$base0 + $dr]) { $upOn = $true }
            if (-not $upOn -and $has1 -and $inR -and $sub[$base1 + $dr]) { $upOn = $true }
            if ($has2) {
                if ($inL -and $sub[$base2 + $dl]) { $loOn = $true }
                if (-not $loOn -and $inR -and $sub[$base2 + $dr]) { $loOn = $true }
            }
            if (-not $loOn -and $has3 -and $inL -and $sub[$base3 + $dl]) { $loOn = $true }
            if (-not $loOn -and $has3 -and $inR -and $sub[$base3 + $dr]) { $loOn = $true }

            if ($mode -eq 'ascii') {
                if ($upOn -or $loOn) { $chars[$i] = [char]35 } else { $chars[$i] = $CH_SPACE }
            } elseif ($upOn -and $loOn) {
                $chars[$i] = $CH_FULL
            } elseif ($upOn) {
                # 终端没有 ▀（如 GBK 代码页）时用 █ 顶替，宁可粗一点也不要问号
                if ($script:GlyphUp) { $chars[$i] = $CH_HALF_UP } else { $chars[$i] = $CH_FULL }
            } elseif ($loOn) {
                if ($script:GlyphDown) { $chars[$i] = $CH_HALF_DOWN } else { $chars[$i] = $CH_FULL }
            } else {
                $chars[$i] = $CH_SPACE
            }
        }
    }
    $slice = -join $chars
    $row = $script:Rows[$r]
    if ($row.Length -ne $script:CharCols) { return $slice }   # 首帧：整行都在这段区间里
    return ($row.Substring(0, $c0) + $slice + $row.Substring($c1 + 1))
}

function Set-RowText([string]$row, [string]$text, [int]$rightMargin) {
    if ([string]::IsNullOrEmpty($text)) { return $row }
    $start = $row.Length - $rightMargin - $text.Length
    if ($start -lt 0) { $start = 0 }
    $chars = $row.ToCharArray()
    for ($i = 0; $i -lt $text.Length; $i++) {
        $p = $start + $i
        if ($p -ge 0 -and $p -lt $chars.Length) { $chars[$p] = $text[$i] }
    }
    return (-join $chars)
}

function Render-Frame {
    [Array]::Clear($script:Sub, 0, $script:Sub.Length)

    # ── 换幕：自下而上的「幕布」+ 每行独立走 旧色→灰→目标色 三档 ──
    # 关键：不再整屏统一改底色（那会造成整屏跳灰、遮画面、前后景同色看不见字），
    #       而是每一行各自按状态上色，并被幕布逐步扫过。
    if ($script:PhaseChanged) {
        $script:PhaseChanged = $false
        $target = 'Black'
        if ($script:Phase -eq 1) { $target = 'White' }
        if ($script:FirstPaint) {
            $script:FirstPaint = $false
            for ($r = 0; $r -lt $script:TermRows; $r++) { $script:RowState[$r] = 3; $script:RowTimer[$r] = 0.0 }
            $script:FadeFrom = $target
            $script:FadeTo = $target
            $script:CurBg = $target
            $script:CurtainRow = -1
            if (-not $script:Headless) {
                try {
                    [Console]::BackgroundColor = [ConsoleColor]$target
                    [Console]::ForegroundColor = [ConsoleColor](Get-ContrastFg $target)
                } catch { }
            }
            $script:NeedFullRepaint = $true
        } else {
            $script:DotFg = 'White'                                  # 去黑天：灰/黑底上用白点
            if ($script:Phase -eq 1) { $script:DotFg = 'Black' }      # 去天亮：灰/白底上用黑点
            for ($r = 0; $r -lt $script:TermRows; $r++) { $script:RowState[$r] = 0; $script:RowTimer[$r] = 0.0 }
            $script:FadeFrom = $script:CurBg
            $script:FadeTo = $target
            $script:CurtainRow = $script:TermRows - 1
            $script:CurtainClock = 0.0
        }
    }
    if ($script:CurtainRow -ge 0) {
        $script:CurtainClock += 16.667
        if ($script:CurtainClock -ge 137.0) {                 # 每 137ms 幕布上移一行（≈原来的 2.5 倍时长）
            $script:CurtainClock = 0.0
            $cr = $script:CurtainRow
            if (($cr -ge 0) -and ($cr -lt $script:TermRows)) {
                $script:RowState[$cr] = 1
                $script:RowTimer[$cr] = 0.0
                if ($cr -ge $script:FieldRows) {
                    Write-RowFill $cr
                    if ($cr -eq $script:FieldRows) { $script:PrevStatus = '' }   # 状态行要跟着重写底色
                }
            }
            $script:CurtainRow--
            if ($script:CurtainRow -lt 0) { $script:CurBg = $script:FadeTo }
            $script:NeedFullRepaint = $true
        }
    }
    # 每行依次走：旧色 → L1点层 → L2纯灰 → L3点层 → L4目标色（顺序固定）
    for ($r = 0; $r -lt $script:TermRows; $r++) {
        $st = 4
        if (($r -ge 0) -and ($r -lt $script:RowState.Count)) { $st = $script:RowState[$r] }
        if (($st -ge 1) -and ($st -le 3)) {
            $script:RowTimer[$r] += 16.667
            $need = 520.0                                        # L1 / L3 点层停留 520ms
            if ($st -eq 2) { $need = 660.0 }                     # L2 灰层停留 660ms
            if ($script:RowTimer[$r] -ge $need) {
                $script:RowState[$r] = $st + 1
                $script:RowTimer[$r] = 0.0
                if ($r -ge $script:FieldRows) {
                    Write-RowFill $r
                    if ($r -eq $script:FieldRows) { $script:PrevStatus = '' }
                }
                $script:NeedFullRepaint = $true
            }
        }
    }
    if ($script:NeedFullRepaint) {
        $script:NeedFullRepaint = $false
        for ($r = 0; $r -lt $script:FieldRows; $r++) {
            $script:PrevMin[$r] = 0
            $script:PrevMax[$r] = $script:CharCols - 1
            $script:Rows[$r] = ''
            $script:Screen[$r] = ''
        }
    }

    Draw-World

    $g = $script:G
    $m = $g.meter

    # 上一帧的撞毁提示行必须整行重绘，才能把文字擦掉
    if ($script:OverlayRows.Count -gt 0) {
        foreach ($or in $script:OverlayRows) {
            $script:DirtyMin[$or] = 0
            $script:DirtyMax[$or] = $script:CharCols - 1
        }
        $script:OverlayRows.Clear()
    }

    # 只重组「本帧或上一帧被改动」的列区间（离开的图形要再擦一次，否则留残影）
    for ($r = 0; $r -lt $script:FieldRows; $r++) {
        $c0 = $script:DirtyMin[$r]
        $c1 = $script:DirtyMax[$r]
        if ($script:PrevMin[$r] -lt $c0) { $c0 = $script:PrevMin[$r] }
        if ($script:PrevMax[$r] -gt $c1) { $c1 = $script:PrevMax[$r] }
        if ($script:Rows[$r].Length -ne $script:CharCols) { $c0 = 0; $c1 = $script:CharCols - 1 }
        if ($c1 -lt $c0) { continue }
        $script:Rows[$r] = Compose-Slice $r $c0 $c1
    }
    [Array]::Copy($script:DirtyMin, $script:PrevMin, $script:FieldRows)
    [Array]::Copy($script:DirtyMax, $script:PrevMax, $script:FieldRows)
    for ($r = 0; $r -lt $script:FieldRows; $r++) {
        $script:DirtyMin[$r] = [int]::MaxValue
        $script:DirtyMax[$r] = -1
    }

    # 分数覆盖层（原版画在 y=5，这里放第 0 行右侧）
    if ($script:FieldRows -gt 0) {
        $scoreStr = $m.digits -join ''
        if ($m.achievement -and $m.flashTimer -lt $C.FLASH_DURATION) { $scoreStr = ' ' * $m.maxScoreUnits }
        $row0 = Set-RowText $script:Rows[0] $scoreStr 1
        $script:Rows[0] = Set-RowText $row0 $m.highScoreStr (2 + $m.maxScoreUnits)
    }

    # 撞毁提示
    if ($g.crashed -and $script:FieldRows -ge 4) {
        $r1 = [int]($script:FieldRows / 2) - 1
        foreach ($pair in @(@($r1, 'G A M E   O V E R'), @(($r1 + 2), 'Press Enter to restart'))) {
            $idx = [int]$pair[0]
            if ($idx -lt 0 -or $idx -ge $script:FieldRows) { continue }
            $pad = [int](($script:CharCols - $pair[1].Length) / 2)
            if ($pad -lt 0) { $pad = 0 }
            $rowX = ((' ' * $pad) + $pair[1]).PadRight($script:CharCols)
            if ($rowX.Length -gt $script:CharCols) { $rowX = $rowX.Substring(0, $script:CharCols) }
            $script:Rows[$idx] = $rowX
            [void]$script:OverlayRows.Add($idx)
        }
    }

    # 与屏幕内容比对，只写真正变化的行
    $changed = [System.Collections.Generic.List[int]]::new()
    for ($r = 0; $r -lt $script:FieldRows; $r++) {
        if ($script:Rows[$r] -ne $script:Screen[$r]) { $changed.Add($r) }
    }
    foreach ($r in $changed) {
        if (-not $script:Headless) {
            try {
                # 每一行按它「当前该是什么底色/前景」上色：
                # 幕布扫过时，屏幕上会同时存在 旧色/点层/灰层/目标色 四种区域
                $bgN = Get-RowBg $r
                [Console]::BackgroundColor = [ConsoleColor]$bgN
                [Console]::ForegroundColor = [ConsoleColor](Get-RowFg $r)
                [Console]::SetCursorPosition(0, $r)
                [Console]::Write($script:Rows[$r])
                $script:RenderFail = 0
            } catch { $script:RenderFail++ }
        }
        $script:Screen[$r] = $script:Rows[$r]
    }

    # 状态行
    $t = $g.trex
    $state = 'READY'
    if ($g.crashed) { $state = 'CRASHED' }
    elseif ($t.ducking) { $state = 'DUCK' }
    elseif ($t.jumping) { $state = 'JUMP' }
    elseif ($g.playing) { $state = 'RUN' }
    $phaseName = '夜晚'
    if ($script:Phase -eq 1) { $phaseName = '天亮' }
    elseif ($script:Phase -eq 2) { $phaseName = '繁星夜' }
    $status = ('  空格/↑ 跳  ↓ 蹲  Enter 重开  Esc 退出   |  速度 {0:0.000}  {1}  {2}  {3}' -f `
        $g.currentSpeed, $state, $phaseName, $m.highScoreStr)
    $status = $status.PadRight($script:CharCols)
    if ($status.Length -gt $script:CharCols) { $status = $status.Substring(0, $script:CharCols) }
    if (-not $script:Headless) {
        if ($status -ne $script:PrevStatus) {
            try {
                $bgN = Get-RowBg $script:FieldRows
                [Console]::BackgroundColor = [ConsoleColor]$bgN
                [Console]::ForegroundColor = [ConsoleColor](Get-ContrastFg $bgN)
                [Console]::SetCursorPosition(0, $script:FieldRows)
                [Console]::Write($status)
                $script:PrevStatus = $status
            } catch { $script:RenderFail++ }
        }
    }
}
#endregion

#region ── 输入 ─────────────────────────────────────────────────────────────────
$script:UseAsyncKeys = $false
$script:FocusOnly = $false
$script:KeyHeld = @{ Space = $false; Up = $false; Down = $false; Enter = $false; Esc = $false }

function Initialize-Input {
    try {
        if (-not ('Dino.Native' -as [type])) {
            # 必须接住返回值：Add-Type 会把生成的类型对象写进管道，
            # 脚本结束时 PowerShell 会一次性打印它们 —— 这就是"退出时输出一堆东西"
            $null = Add-Type -Namespace Dino -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern short GetAsyncKeyState(int vKey);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
'@ -ErrorAction Stop
        }
        $script:UseAsyncKeys = $true
    } catch {
        $script:UseAsyncKeys = $false
    }
}

function Get-KeySnapshot {
    $s = @{ Space = $false; Up = $false; Down = $false; Enter = $false; Esc = $false }
    if ($script:UseAsyncKeys) {
        # -FocusOnly：终端窗口不在前台时一律当作"没按键"（防止在别的窗口打字操控恐龙）
        if ($script:FocusOnly) {
            $fg = [Dino.Native]::GetForegroundWindow()
            $cw = [Dino.Native]::GetConsoleWindow()
            if (($fg -ne [IntPtr]::Zero) -and ($cw -ne [IntPtr]::Zero) -and ($fg -ne $cw)) { return $s }
        }
        $s.Space = (([Dino.Native]::GetAsyncKeyState(0x20)) -band 0x8000) -ne 0
        $s.Up    = (([Dino.Native]::GetAsyncKeyState(0x26)) -band 0x8000) -ne 0
        $s.Down  = (([Dino.Native]::GetAsyncKeyState(0x28)) -band 0x8000) -ne 0
        $s.Enter = (([Dino.Native]::GetAsyncKeyState(0x0D)) -band 0x8000) -ne 0
        $s.Esc   = (([Dino.Native]::GetAsyncKeyState(0x1B)) -band 0x8000) -ne 0
    } else {
        try {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                switch ($k.Key) {
                    ([ConsoleKey]::Spacebar)  { $s.Space = $true }
                    ([ConsoleKey]::UpArrow)   { $s.Up    = $true }
                    ([ConsoleKey]::DownArrow) { $s.Down  = $true }
                    ([ConsoleKey]::Enter)     { $s.Enter = $true }
                    ([ConsoleKey]::Escape)    { $s.Esc   = $true }
                }
            }
        } catch {
            # 没有可交互控制台（stdin 被重定向等）：不要让整个脚本被异常带走
            $script:UseAsyncKeys = $false
        }
    }
    return $s
}
#endregion

#region ── 输入 → 动作（offline.ts · onKeyDown / onKeyUp） ──────────────────────
function Apply-Input([hashtable]$now, [double]$elapsedMs) {
    $g = $script:G
    $t = $g.trex

    $jumpDown = ($now.Space -and -not $script:KeyHeld.Space) -or ($now.Up -and -not $script:KeyHeld.Up)
    $jumpUp   = ((-not $now.Space) -and $script:KeyHeld.Space) -or ((-not $now.Up) -and $script:KeyHeld.Up)
    $downDown = $now.Down -and -not $script:KeyHeld.Down
    $downUp   = (-not $now.Down) -and $script:KeyHeld.Down
    $enterDown = $now.Enter -and -not $script:KeyHeld.Enter
    # 规格 §14.4/§15.3：重开走的是 keyup，不是 keydown
    $enterUp = (-not $now.Enter) -and $script:KeyHeld.Enter

    if ($now.Esc) { return 'quit' }

    if ($g.crashed) {
        # 撞毁后：Enter 松手立刻重开；空格/↑ 松手且已过 gameoverClearTime(1200ms)
        $canRestart = $enterUp -or ($jumpUp -and ($elapsedMs -ge $C.GAMEOVER_CLEAR_TIME))
        if ($canRestart) {
            Restart-Game
        }
    } else {
        if ($jumpDown) {
            if (-not $g.playing) {
                $g.playing = $true
                $g.activated = $true
                Reset-SpeedTo $C.SPEED
            }
            if ((-not $t.jumping) -and (-not $t.ducking)) { Start-Jump $g.currentSpeed }
        }
        if ($jumpUp) {
            if ($g.playing) { End-Jump }
        }
        # 空中：只在「按下的那一帧」触发速降 —— 每帧都触发会把 jumpVelocity 不断重置回 1，
        # 下落就永远加速不起来（上一版就是这么把速降改坏的）。
        # 落地后仍按着 ↓ → 立刻下蹲（原版靠按键自动重复实现，这里用持续按住等价实现）。
        if ($now.Down -and $g.playing) {
            if ($t.jumping) {
                if ($downDown) { Set-SpeedDrop }
            } elseif (-not $t.ducking) { Set-Duck $true }
        }
        if ($downUp) {
            $t.speedDrop = $false
            Set-Duck $false
        }
    }

    $script:KeyHeld.Space = $now.Space
    $script:KeyHeld.Up    = $now.Up
    $script:KeyHeld.Down  = $now.Down
    $script:KeyHeld.Enter = $now.Enter
    $script:KeyHeld.Esc   = $now.Esc
    return 'ok'
}

function Restart-Game {
    # offline.ts · restart（不清 obstacleHistory，照抄原版）
    $g = $script:G
    $g.runningTime  = 0.0
    $g.crashed      = $false
    $g.playing      = $true
    $g.distanceRan  = 0.0
    Reset-SpeedTo $C.SPEED
    $g.obstacles    = @()
    $g.meter.achievement = $false
    $g.meter.flashIterations = 0
    $g.meter.flashTimer = 0.0
    $g.meter.digits = @('0','0','0','0','0')
    $g.meter.maxScoreUnits = $C.MAX_DISTANCE_UNITS
    $g.meter.maxScore = 99999
    $g.inverted = $false
    $g.invertTimer = 0.0
    Reset-Trex
    $g.playing = $true
}
#endregion

#region ── 自检（-Simulate） ────────────────────────────────────────────────────
function Invoke-Simulation {
    $results = New-Object 'System.Collections.Generic.List[string]'
    $fail = 0

    function Check([string]$name, [bool]$ok, [string]$detail) {
        $tag = 'PASS'
        if (-not $ok) { $tag = 'FAIL'; $script:SimFail++ }
        $script:SimResults.Add(("[{0}] {1}  {2}" -f $tag, $name, $detail))
    }
    $script:SimResults = $results
    $script:SimFail = 0

    # ── 测试 1：跳跃轨迹（对照规格 §8.6 的逐帧表）
    $script:G = New-Game 600
    Reset-SpeedTo $C.SPEED
    $script:G.playing = $true
    $script:G.trex.status = $STATUS_RUNNING
    Start-Jump $script:G.currentSpeed
    $trace = @()
    $landFrame = 0
    for ($i = 1; $i -le 40; $i++) {
        Step-Frame $C.MS_PER_FRAME
        $trace += [int][Math]::Round($script:G.trex.yPos)
        if ((-not $script:G.trex.jumping) -and $landFrame -eq 0) { $landFrame = $i }
    }
    # 规格 §8.6 的逐帧量化示例（speed=6，长按不松）
    $expect = @(82,72,63,54,46,38,31,25,20,16,12,9,6,4,3,2,2,2,3,5,7,10,13,17,22,27,33,39,46,54,62,71,80,90,93)
    $head = ($trace[0..6] -join ',')
    Check '跳跃轨迹前 7 帧 (82,72,63,54,46,38,31)' ($head -eq '82,72,63,54,46,38,31') ("实际: $head")
    $mismatch = -1
    for ($i = 0; $i -lt $expect.Count; $i++) {
        if ($trace[$i] -ne $expect[$i]) { $mismatch = $i + 1; break }
    }
    $detail = '35 帧全部一致'
    if ($mismatch -gt 0) {
        $detail = "第 $mismatch 帧：实际 $($trace[$mismatch-1])，期望 $($expect[$mismatch-1])"
    }
    Check '前 35 帧轨迹逐帧一致' ($mismatch -lt 0) $detail
    $peak = ($trace | Measure-Object -Minimum).Minimum
    Check '长按峰值 yPos ≈ 2 (跳高≈91px)' ($peak -le 3) ("实际峰值: $peak")
    Check '滞空 ≈35 帧' (($landFrame -ge 34) -and ($landFrame -le 36)) ("实际落地帧: $landFrame")

    # ── 测试 2：速度曲线（走真实 Step-Frame 代码路径；每帧把 runningTime 归零以屏蔽障碍）
    $script:G = New-Game 600
    Reset-SpeedTo $C.SPEED
    $script:G.playing = $true
    $script:G.trex.status = $STATUS_RUNNING
    $f = 0
    while ($script:G.currentSpeed -lt $C.MAX_SPEED -and $f -lt 40000) {
        $script:G.runningTime = 0.0
        Step-Frame $C.MS_PER_FRAME
        $f++
    }
    # 速度上限与加速度都改了 → 期望帧数由常量算出，别再写死
    $expectFrames = [int][Math]::Ceiling(($C.MAX_SPEED - $C.SPEED) / $C.ACCELERATION)
    Check ("6→{0} 需 {1} 帧（加速度 {2}）" -f $C.MAX_SPEED, $expectFrames, $C.ACCELERATION) `
        (($f -ge $expectFrames) -and ($f -le ($expectFrames + 1))) ("实际: $f 帧")

    $script:G = New-Game 600
    Reset-SpeedTo $C.SPEED
    $script:G.playing = $true
    $script:G.trex.status = $STATUS_RUNNING
    for ($i = 0; $i -lt 60; $i++) { $script:G.runningTime = 0.0; Step-Frame $C.MS_PER_FRAME }
    $d60 = $script:G.distanceRan
    Check '首秒距离 ≈ 361px（速度 6→6.06）' (($d60 -ge 360) -and ($d60 -le 362)) ("实际: {0:0.00}" -f $d60)
    Check '首秒分数 ≈ 9（对应用户感知的 9 分/秒）' ((Get-ActualDistance $d60) -eq 9) ("实际: $(Get-ActualDistance $d60)")

    # ── 测试 3：障碍生成统计（把 T-Rex 挪到画布外，避免撞死打断生成）
    $script:G = New-Game 600
    Reset-SpeedTo $C.SPEED
    $script:G.playing = $true
    $script:G.trex.status = $STATUS_RUNNING
    $stats = @{ cactusSmall = 0; cactusLarge = 0; pterodactyl = 0 }
    $firstPtero = -1
    $phase2Frame = -1
    $gapBad = 0; $gapChecked = 0; $badSize = 0; $mixedGroups = 0
    $lastId = -1
    $sizesSeen = @{}
    $order = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 1; $i -le $SimulateFrames; $i++) {
        $script:G.trex.xPos = -5000.0
        Step-Frame $C.MS_PER_FRAME
        if (($phase2Frame -lt 0) -and ($script:Phase -eq 2)) { $phase2Frame = $i }
        foreach ($o in $script:G.obstacles) {
            if ($o.id -gt $lastId) {
                $lastId = $o.id
                $stats[$o.type]++
                $order.Add($o.type)
                if ($o.type -eq 'pterodactyl' -and $firstPtero -lt 0) { $firstPtero = $i }
                $sizesSeen["$($o.type)/$($o.size)"] = $true
                if (($o.size -gt 1) -and ($o.typeConfig.multipleSpeed -gt $o.createSpeed)) { $badSize++ }
                if ($null -ne $o.units) { $mixedGroups++ }
                # 间隔要按新的难度系数校验
                $gf = Get-GapScale $o.createSpeed $o.type
                $minGap = [int][Math]::Round((Get-JsRound ($o.width * $o.createSpeed + $o.typeConfig.minGap * $C.GAP_COEFFICIENT)) * $gf)
                $maxGap = [int][Math]::Round((Get-JsRound ((Get-JsRound ($o.width * $o.createSpeed + $o.typeConfig.minGap * $C.GAP_COEFFICIENT)) * $C.MAX_GAP_COEFFICIENT)) * $gf)
                if ($minGap -lt 90) { $minGap = 90 }
                if ($maxGap -lt $minGap) { $maxGap = $minGap }
                $gapChecked++
                if (($o.gap -lt $minGap) -or ($o.gap -gt $maxGap)) { $gapBad++ }
            }
        }
    }
    $spawned = $stats['cactusSmall'] + $stats['cactusLarge'] + $stats['pterodactyl']
    Check '有障碍生成' ($spawned -gt 0) ("$SimulateFrames 帧内生成 $spawned 个（小仙人掌 $($stats['cactusSmall'])、大仙人掌 $($stats['cactusLarge'])、翼龙 $($stats['pterodactyl'])）")
    # 速度阈值是硬约束：speed 从 6 起每帧 +ACCELERATION，达到 8.5 需要的帧数由常量算出
    $pteroFrame = [int][Math]::Floor((8.5 - $C.SPEED) / $C.ACCELERATION)
    $expectPtero = $pteroFrame
    if ($phase2Frame -gt $expectPtero) { $expectPtero = $phase2Frame }
    Check ("翼龙首次出现在「速度阈值」与「第三幕」之后（≥{0}）" -f $expectPtero) `
        (($firstPtero -ge ($expectPtero - 10)) -and ($firstPtero -le ($expectPtero + 1200))) `
        ("实际第 $firstPtero 帧；速度阈值 {0} 帧，第三幕始于 {1} 帧" -f $pteroFrame, $phase2Frame)
    Check '翼龙不会在第三幕之前出现' (($phase2Frame -lt 0) -or ($firstPtero -ge $phase2Frame)) `
        ("第三幕始于 $phase2Frame 帧，首只翼龙 $firstPtero 帧")
    Check '所有 gap 落在公式闭区间内' ($gapBad -eq 0) ("校验 $gapChecked 个，越界 $gapBad 个")
    Check '多连体仅在速度达标时出现' ($badSize -eq 0) ("违规 $badSize 个")
    Check '出现「大小仙人掌混排」的连体组' ($mixedGroups -gt 0) ("混排组 $mixedGroups 个")
    $maxRun = 0; $run = 0; $prevType = ''
    foreach ($ty in $order) {
        if ($ty -eq $prevType) { $run++ } else { $run = 1; $prevType = $ty }
        if ($run -gt $maxRun) { $maxRun = $run }
    }
    Check '连续同类型不超过 2 个（maxObstacleDuplication）' ($maxRun -le 2) ("实际最长连续: $maxRun")
    Check '翼龙 size 恒为 1' ((-not $sizesSeen.ContainsKey('pterodactyl/2')) -and (-not $sizesSeen.ContainsKey('pterodactyl/3'))) ((($sizesSeen.Keys | Where-Object { $_ -like 'pterodactyl/*' }) -join ','))
    Check '出现过 2/3 连体仙人掌' ($sizesSeen.ContainsKey('cactusSmall/2') -or $sizesSeen.ContainsKey('cactusSmall/3')) ((($sizesSeen.Keys | Where-Object { $_ -like 'cactus*' }) -join ','))

    # ── 测试 4：短按 vs 长按
    $script:G = New-Game 600
    Reset-SpeedTo $C.SPEED
    $script:G.playing = $true
    $script:G.trex.status = $STATUS_RUNNING
    Start-Jump $script:G.currentSpeed
    $shortPeak = 999
    for ($i = 1; $i -le 40; $i++) {
        if ($i -eq 5) { End-Jump }              # 第 5 帧松手
        Step-Frame $C.MS_PER_FRAME
        if (-not $script:G.trex.jumping) { break }
        if ($script:G.trex.yPos -lt $shortPeak) { $shortPeak = [int][Math]::Round($script:G.trex.yPos) }
    }
    Check '短按峰值低于长按峰值' ($shortPeak -gt $peak) ("短按峰值 $shortPeak vs 长按峰值 $peak")

    # ── 测试 5：分数换算
    $script:G = New-Game 600
    $script:G.distanceRan = 1000.0
    $s = Get-ActualDistance 1000.0
    Check 'score = round(ceil(1000)*0.025) = 25' ($s -eq 25) ("实际: $s")
    # 这条专门抓「ceil 漏写」：19.9 → ceil 20 → 20*0.025=0.5 → round=1（漏 ceil 会得 0）
    Check 'score = round(ceil(19.9)*0.025) = 1（ceil 不可漏）' ((Get-ActualDistance 19.9) -eq 1) ("实际: $(Get-ActualDistance 19.9)")
    Check '40px = 1 分（每 40px 一分）' ((Get-ActualDistance 40) -eq 1) ("实际: $(Get-ActualDistance 40)")
    $script:G.distanceRan = 0.0
    Check 'distance=0 → score 0' ((Get-ActualDistance 0.0) -eq 0) ''

    # ── 测试 6：碰撞盒几何（规格 §10.2 的下蹲裁剪陷阱 / §10.3 的 size 改写）
    $script:G = New-Game 600
    $script:G.trex.ducking = $true
    $script:G.trex.status = $STATUS_DUCKING
    $oCactus = New-Obstacle $ObstacleTypes[0] 6.0 1
    $oCactus.xPos = 80.0; $oCactus.yPos = 105.0
    $hitDuckNear = Test-Collision $oCactus
    $oCactus.xPos = 95.0
    $hitDuckFar = Test-Collision $oCactus
    Check '下蹲时 x=80 的仙人掌命中' $hitDuckNear ("实际: $hitDuckNear")
    Check '下蹲时 x=95 不命中（55px 子盒被外层 42px 裁掉）' (-not $hitDuckFar) ("实际: $hitDuckFar")

    $script:G = New-Game 600
    $script:G.trex.status = $STATUS_RUNNING
    $oStand = New-Obstacle $ObstacleTypes[0] 6.0 1
    $oStand.xPos = 80.0; $oStand.yPos = 105.0
    Check '站立时 x=80 命中（头部子盒 73–90 / 94–110）' (Test-Collision $oStand) ''

    $oBig = New-Obstacle $ObstacleTypes[0] 13.0 3
    Check 'size=3 小仙人掌 width=51' ($oBig.width -eq 51) ("实际: $($oBig.width)")
    Check 'size=3 盒1宽度被改写为 39' ($oBig.boxes[1][2] -eq 39) ("实际: $($oBig.boxes[1][2])")
    Check 'size=3 盒2.x 被改写为 44' ($oBig.boxes[2][0] -eq 44) ("实际: $($oBig.boxes[2][0])")

    # cactusLarge 的 multipleSpeed = 7：speed=6 时必须被强制压回 size 1（原版行为）
    $oLargeLow = New-Obstacle $ObstacleTypes[1] 6.0 2
    Check 'speed=6 时大仙人掌被压回 size=1（multipleSpeed=7）' (($oLargeLow.size -eq 1) -and ($oLargeLow.width -eq 25)) ("实际 size=$($oLargeLow.size) width=$($oLargeLow.width)")

    # speed=8 时允许 2 连体
    $oLarge = New-Obstacle $ObstacleTypes[1] 8.0 2
    Check 'speed=8 时大仙人掌 size=2 width=50' (($oLarge.size -eq 2) -and ($oLarge.width -eq 50)) ("实际 size=$($oLarge.size) width=$($oLarge.width)")
    Check 'size=2 大仙人掌盒1宽度被改写为 33' ($oLarge.boxes[1][2] -eq 33) ("实际: $($oLarge.boxes[1][2])")

    Write-Host ''
    Write-Host '===== ChromeDino 物理自检 =====' -ForegroundColor Cyan
    foreach ($r in $results) {
        if ($r.StartsWith('[FAIL]')) { Write-Host $r -ForegroundColor Red }
        else { Write-Host $r -ForegroundColor Green }
    }
    Write-Host ''
    Write-Host ("共 {0} 项，失败 {1} 项" -f $results.Count, $script:SimFail)
    if ($script:SimFail -gt 0) { exit 1 } else { exit 0 }
}
#endregion

#region ── 渲染快照 + 机器人试玩（-Dump） ────────────────────────────────────────
function Invoke-Dump {
    $script:TermCols = 100
    $script:TermRows = 40
    Initialize-RowStates
    $script:Headless = $true
    Initialize-Buffers $CanvasWidth
    [void](Resolve-RenderMode $Render ([bool]$Ascii))
    $script:G = New-Game $CanvasWidth
    Reset-SpeedTo $C.SPEED
    $script:G.playing = $true
    Reset-Trex

    $shotAt = @(120, 2600, 3000, 3600, 4600)
    $snaps = @{}
    $autoJumps = 0
    $survivedTo = 0
    $pteroY = @{}

    for ($i = 1; $i -le $DumpFrames; $i++) {
        # 强制下蹲窗口：验证下蹲姿态与截图
        if ($i -eq 2580) { Set-Duck $true }
        if ($i -eq 2640) { Set-Duck $false }
        foreach ($o in $script:G.obstacles) {
            if ($o.type -eq 'pterodactyl') { $pteroY[[int]$o.yPos] = $true }
        }
        # ── 机器人：看最近的障碍决定跳/蹲，保证长跑不死 ──
        $t = $script:G.trex
        $speed = $script:G.currentSpeed
        $nearest = $null
        foreach ($o in $script:G.obstacles) {
            if (($o.xPos + $o.width) -gt $t.xPos) {
                if ($null -eq $nearest -or $o.xPos -lt $nearest.xPos) { $nearest = $o }
            }
        }
        $wantDuck = $false
        if ($null -ne $nearest) {
            $dist = $nearest.xPos - $t.xPos
            if ($nearest.type -eq 'pterodactyl') {
                # 原版三档高度：50 从头顶掠过无需动作；75 必须下蹲；100 太低，必须跳过去
                if ([int]$nearest.yPos -eq 75) {
                    if (($dist -lt ($speed * 7)) -and ($dist -gt -40)) { $wantDuck = $true }
                } elseif ([int]$nearest.yPos -ge 90) {
                    if ((-not $t.jumping) -and (-not $t.ducking) -and
                        ($dist -lt ($speed * 9)) -and ($dist -gt ($speed * 1.5))) {
                        Start-Jump $speed
                        $autoJumps++
                    }
                }
            } elseif ((-not $t.jumping) -and (-not $t.ducking) -and
                      ($dist -lt ($speed * 9)) -and ($dist -gt ($speed * 1.5))) {
                Start-Jump $speed
                $autoJumps++
            }
        }
        if ($wantDuck -and (-not $t.jumping) -and (-not $t.ducking)) { Set-Duck $true }
        elseif ((-not $wantDuck) -and $t.ducking) { Set-Duck $false }

        Step-Frame $C.MS_PER_FRAME
        $survivedTo = $i

        if ($shotAt -contains $i) {
            Render-Frame
            $snaps[$i] = @{
                rows  = @($script:Rows)
                speed = $script:G.currentSpeed
                score = $script:G.meter.score
                yPos  = $script:G.trex.yPos
                state = $script:G.trex.status
            }
        }
    }

    $g = $script:G
    $crashedAtEnd = [bool]$g.crashed
    Write-Host ''
    Write-Host '===== ChromeDino 渲染快照 + 机器人试玩 =====' -ForegroundColor Cyan
    Write-Host ("帧数: {0}   画布: {1}x{2}px   网格: {3}列 x {4}字符行   机器人起跳: {5} 次" -f `
        $DumpFrames, $g.canvasW, $C.CANVAS_HEIGHT, $script:Cols, $script:FieldRows, $autoJumps)
    Write-Host ("结束状态: 速度 {0:0.000}   分数 {1}   撞毁 {2}   障碍在屏 {3} 个" -f `
        $g.currentSpeed, $g.meter.score, $g.crashed, $g.obstacles.Count)
    Write-Host ("翼龙出现过的飞行高度: {0}" -f (($pteroY.Keys | Sort-Object) -join ', '))
    Write-Host ''

    foreach ($k in ($shotAt | Sort-Object)) {
        if (-not $snaps.ContainsKey($k)) { continue }
        $snap = $snaps[$k]
        Write-Host ("──── 第 {0} 帧 ────" -f $k) -ForegroundColor Yellow
        foreach ($row in $snap.rows) {
            Write-Host ('|' + $row + '|')
        }
        $stName = 'RUN'
        if ($snap.state -eq $STATUS_JUMPING) { $stName = 'JUMP' }
        elseif ($snap.state -eq $STATUS_DUCKING) { $stName = 'DUCK' }
        elseif ($snap.state -eq $STATUS_CRASHED) { $stName = 'CRASHED' }
        elseif ($snap.state -eq $STATUS_WAITING) { $stName = 'WAITING' }
        Write-Host ('[该帧状态] 速度 {0:0.000}  分数 {1}  yPos {2:0}  状态 {3}' -f `
            $snap.speed, $snap.score, $snap.yPos, $stName) -ForegroundColor DarkGray
        Write-Host ''
    }

    # ── 点阵原样预览：把精灵图按「点」逐格打印，绕过终端字符集，直接验证形状 ──
    function Show-DotArt([int]$px, [int]$py, [int]$pw, [int]$ph, [string]$label) {
        $d0 = [int][Math]::Floor($px / [double]$PX_PER_DOT_X)
        $d1 = [int][Math]::Floor(($px + $pw - 1) / [double]$PX_PER_DOT_X)
        $r0 = [int][Math]::Floor($py / [double]$PX_PER_DOT_Y)
        $r1 = [int][Math]::Floor(($py + $ph - 1) / [double]$PX_PER_DOT_Y)
        Write-Host ("  {0}   点阵 {1} x {2}" -f $label, ($d1 - $d0 + 1), ($r1 - $r0 + 1)) -ForegroundColor Yellow
        for ($r = $r0; $r -le $r1; $r++) {
            if ($r -lt 0 -or $r -ge $script:SubRows) { continue }
            $base = $r * $script:Cols
            $sb = [System.Text.StringBuilder]::new()
            for ($c = $d0; $c -le $d1; $c++) {
                if ($c -lt 0 -or $c -ge $script:Cols) { [void]$sb.Append(' '); continue }
                if ($script:Sub[$base + $c]) { [void]$sb.Append('#') } else { [void]$sb.Append('.') }
            }
            Write-Host ('  ' + $sb.ToString())
        }
        Write-Host ''
    }
    Write-Host '──── 精灵点阵预览（# = 亮点，. = 空；这里是渲染前的真实形状）────' -ForegroundColor Cyan
    $g2 = $script:G
    $savedObs = $g2.obstacles
    $savedDuck = $g2.trex.ducking
    $savedJump = $g2.trex.jumping
    $savedStat = $g2.trex.status

    $g2.obstacles = @()
    $g2.trex.ducking = $false; $g2.trex.jumping = $false; $g2.trex.status = $STATUS_RUNNING
    Render-Frame
    Show-DotArt ([int]$g2.trex.xPos) ([int]$g2.trex.yPos) $C.TREX_WIDTH $C.TREX_HEIGHT '恐龙 · 跑动帧（注意头部的眼睛缺口）'

    $g2.trex.jumping = $true
    Render-Frame
    Show-DotArt ([int]$g2.trex.xPos) ([int]$g2.trex.yPos) $C.TREX_WIDTH $C.TREX_HEIGHT '恐龙 · 跳跃'
    $g2.trex.jumping = $false

    $g2.trex.status = $STATUS_CRASHED
    Render-Frame
    Show-DotArt ([int]$g2.trex.xPos) ([int]$g2.trex.yPos) $C.TREX_WIDTH $C.TREX_HEIGHT '恐龙 · 撞毁'
    $g2.trex.status = $STATUS_RUNNING

    $g2.trex.ducking = $true
    Render-Frame
    Show-DotArt ([int]$g2.trex.xPos) (([int]$g2.trex.yPos) + 22) $C.TREX_WIDTH_DUCK $C.TREX_HEIGHT_DUCK '恐龙 · 下蹲'
    $g2.trex.ducking = $false

    $g2.obstacles = @()
    $g2.obstacles += New-Obstacle $ObstacleTypes[0] 6.0 1
    $g2.obstacles[0].xPos = 300.0; $g2.obstacles[0].yPos = 105.0
    Render-Frame
    Show-DotArt 300 105 17 35 '障碍 · 小仙人掌（宽 17px，比判定盒还窄 1px）'

    $g2.obstacles = @()
    $g2.obstacles += New-Obstacle $ObstacleTypes[1] 8.0 1
    $g2.obstacles[0].xPos = 300.0; $g2.obstacles[0].yPos = 90.0
    Render-Frame
    Show-DotArt 300 90 25 50 '障碍 · 大仙人掌'

    $g2.obstacles = @()
    $g2.obstacles += New-Obstacle $ObstacleTypes[2] 9.0 1
    $g2.obstacles[0].xPos = 300.0; $g2.obstacles[0].yPos = 75.0
    $g2.obstacles[0].currentFrame = 0
    Render-Frame
    Show-DotArt 300 75 46 40 '障碍 · 翼龙（帧 0）'
    $g2.obstacles[0].currentFrame = 1
    Render-Frame
    Show-DotArt 300 75 46 40 '障碍 · 翼龙（帧 1）'

    $g2.obstacles = $savedObs
    $g2.trex.ducking = $savedDuck; $g2.trex.jumping = $savedJump; $g2.trex.status = $savedStat
    Render-Frame

    # ── 字形回退自检：模拟「终端没有 ▀」（GBK 就是这种情况），确认不会画出问号 ──
    $savedUp = $script:GlyphUp
    $savedMode = $script:RenderMode
    $script:GlyphUp = $false
    $script:RenderMode = 'block'
    $script:UseAscii = $false
    Render-Frame
    $badQ = 0; $badUp = 0
    foreach ($rw in $script:Rows) {
        foreach ($ch in $rw.ToCharArray()) {
            if ($ch -eq '?') { $badQ++ }
            if ($ch -eq [char]0x2580) { $badUp++ }
        }
    }
    if (($badQ -eq 0) -and ($badUp -eq 0)) {
        Write-Host '[字形回退] 模拟「终端无 ▀」渲染一帧：问号 0 个、误用 ▀ 0 个  → PASS' -ForegroundColor Green
    } else {
        Write-Host ("[字形回退] 模拟「终端无 ▀」渲染一帧：问号 {0} 个、误用 ▀ {1} 个  → FAIL" -f $badQ, $badUp) -ForegroundColor Red
    }
    $script:GlyphUp = $savedUp
    $script:RenderMode = $savedMode
    $script:UseAscii = ($savedMode -eq 'ascii')

    # 交互路径冒烟测试：初始化输入、读键、处理输入、真实渲染（控制台写入失败会被内部 try 吞掉）
    try {
        Initialize-Input
        $keys = Get-KeySnapshot
        $act = Apply-Input $keys 0.0
        Render-Frame
        Write-Host ("[交互路径] Add-Type/GetAsyncKeyState 可用 = {0}；Get-KeySnapshot 返回 {1} 个字段；Apply-Input = {2}；Render-Frame 未抛异常" -f `
            $script:UseAsyncKeys, $keys.Count, $act) -ForegroundColor Green
        # 再走一遍真实写屏路径（无控制台时异常会被吞掉，这里只为确认不会崩溃）
        $script:Headless = $false
        Render-Frame
        $script:Headless = $true
        Write-Host '[写屏路径] 带 SetCursorPosition/Write 的渲染未崩溃' -ForegroundColor Green
    } catch {
        Write-Host ("[交互路径] 抛出异常: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    # ── 性能基准（无控制台环境下写屏会被 try 吞掉，所以"渲染"只含字符重组开销）
    $bench = 300
    $swb = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $bench; $i++) { Step-Frame $C.MS_PER_FRAME }
    $logicMs = $swb.Elapsed.TotalMilliseconds / $bench
    $swb.Restart()
    for ($i = 0; $i -lt $bench; $i++) { Render-Frame }
    $renderMs = $swb.Elapsed.TotalMilliseconds / $bench
    $totalMs = $logicMs + $renderMs
    $budget = 1000.0 / 60.0
    Write-Host ("[性能] 逻辑 {0:0.00} ms/帧 + 渲染 {1:0.00} ms/帧 = {2:0.00} ms/帧（60fps 预算 {3:0.00} ms）" -f `
        $logicMs, $renderMs, $totalMs, $budget) -ForegroundColor Cyan
    if ($totalMs -le $budget) {
        Write-Host ("[性能] 余量充足：理论上可跑满 {0:0} fps（不含真实写屏开销）" -f (1000.0 / $totalMs)) -ForegroundColor Green
    } else {
        Write-Host ("[性能] 超预算，实际帧率约 {0:0} fps（不含真实写屏开销）" -f (1000.0 / $totalMs)) -ForegroundColor Yellow
    }
    if ($crashedAtEnd) {
        Write-Host '机器人在长跑中撞毁了（说明自动躲避策略不够好，或碰撞判定有问题）' -ForegroundColor Red
    } else {
        Write-Host ("机器人 {0} 帧全程未撞毁" -f $DumpFrames) -ForegroundColor Green
    }
    exit 0
}
#endregion

#region ── 渲染模式解析（逐个字符探测终端能显示哪些） ──────────────────────────
function Resolve-RenderMode([string]$requested, [bool]$forceAscii) {
    # ── 先把控制台切到 UTF-8 ──
    # Write-Host 走宿主通道（Unicode 正常），但游戏逐字符写屏用的是 [Console]::Write，
    # 它按 [Console]::OutputEncoding 编码：控制台若是 GBK/437，方块与盲文点阵会全变成 "?"。
    # 两条通道的编码必须一致，所以这里一起切到 UTF-8。
    try {
        if ([Console]::OutputEncoding.CodePage -ne 65001) {
            $null = & chcp.com 65001 2>$null
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        }
    } catch { }
    $script:GlyphUp = $true; $script:GlyphDown = $true; $script:GlyphFull = $true
    $canBraille = $false
    try {
        $enc = [Console]::OutputEncoding
        $p = [string][char]0x28FF                                            # 盲文满格
        $canBraille = ($enc.GetString($enc.GetBytes($p)) -eq $p)
        # ⚠ GBK(cp936) 里没有 ▀，只探测 █ 会导致半块模式画出一堆问号
        $p = [string][char]0x2580; $script:GlyphUp   = ($enc.GetString($enc.GetBytes($p)) -eq $p)
        $p = [string][char]0x2584; $script:GlyphDown = ($enc.GetString($enc.GetBytes($p)) -eq $p)
        $p = [string][char]0x2588; $script:GlyphFull = ($enc.GetString($enc.GetBytes($p)) -eq $p)
    } catch { }
    $mode = 'ascii'
    if ($forceAscii) { $mode = 'ascii' }
    elseif (($requested -ne 'auto') -and ($requested -ne '')) { $mode = $requested }
    elseif ($canBraille) { $mode = 'braille' }
    elseif ($script:GlyphFull) { $mode = 'block' }   # 缺 ▀/▄ 时用 █ 顶替，见 Compose-Slice
    $script:RenderMode = $mode
    $script:UseAscii = ($mode -eq 'ascii')
    return $mode
}
#endregion

#region ── 字符集自检（-GlyphTest） ──────────────────────────────────────────────
function Invoke-GlyphTest {
    Write-Host ''
    Write-Host '===== 字符显示自检 =====' -ForegroundColor Cyan
    try {
        $enc = [Console]::OutputEncoding
        Write-Host ("终端输出编码: {0}（代码页 {1}）" -f $enc.WebName, $enc.CodePage) -ForegroundColor DarkGray
    } catch { }
    Write-Host ''
    Write-Host 'A) 盲文点阵  →  -Render braille    （最细腻，精灵图有眼睛/腿的细节）' -ForegroundColor Yellow
    Write-Host '   ⣿ ⠿ ⡇ ⠉ ⢹ ⣏ ⠋ ⡏ ⠿'
    Write-Host '   正常应该看到由小圆点组成的方块图案；若是问号或空白，说明不被支持。'
    Write-Host ''
    Write-Host 'B) 半块字符  →  -Render block      （次选）' -ForegroundColor Yellow
    Write-Host '   █ ▀ ▄ ▀▄█▀▄█ ███'
    Write-Host '   正常应该看到实心方块；若是问号，说明不被支持。'
    Write-Host ''
    Write-Host 'C) 纯 ASCII  →  -Render ascii      （最保险，任何终端都能显示，但细节最粗）' -ForegroundColor Yellow
    Write-Host '   ##########  ##  ####  ######'
    Write-Host ''
    Write-Host '哪一组正常，就用对应的参数运行，例如：' -ForegroundColor Green
    Write-Host '   pwsh -File "D:\Test_DSH\ChromeDino.ps1" -Render braille' -ForegroundColor Cyan
    Write-Host '（默认是 auto：会自动挑一个当前终端能编码的，但字体缺字时它检测不出来，' -ForegroundColor DarkGray
    Write-Host '  这种情况请用手动指定。）' -ForegroundColor DarkGray
    Write-Host ''
}
#endregion

#region ── 主循环 ───────────────────────────────────────────────────────────────
function Start-GameLoop {
    Initialize-Terminal

    # 画布宽度：不超过终端可用列数（一个字符列 = PX_PER_DOT_X * DOTS_PER_CHAR_X 逻辑像素）
    $pxPerCharX = $PX_PER_DOT_X * $DOTS_PER_CHAR_X
    $maxCols = $script:TermCols - 1
    $cols = [int][Math]::Floor($CanvasWidth / $pxPerCharX)
    if ($cols -gt $maxCols) { $cols = $maxCols }
    if ($cols -lt 20) {
        Write-Host ''
        Write-Host ("终端太窄：检测到 {0} 列（完整画布需要 {1} 列；当前 CanvasWidth={2}px）。" -f `
            $script:TermCols, ([int][Math]::Ceiling(600 / [double]$pxPerCharX) + 1), $CanvasWidth) -ForegroundColor Yellow
        Write-Host '如果你明明已经把窗口拉得很宽，多半是「把脚本内容粘贴进控制台」导致的：' -ForegroundColor Yellow
        Write-Host '粘贴执行时 param(...) 不生效，CanvasWidth 会取不到值。请改用脚本文件方式运行：' -ForegroundColor Yellow
        Write-Host '    pwsh -ExecutionPolicy Bypass -File "D:\Test_DSH\ChromeDino.ps1"' -ForegroundColor Cyan
        return
    }
    $canvasW = $cols * $pxPerCharX

    $fieldRows = [int][Math]::Ceiling([int][Math]::Ceiling($C.CANVAS_HEIGHT / [double]$PX_PER_DOT_Y) / [double]$DOTS_PER_CHAR_Y)
    if ($script:TermRows -lt ($fieldRows + 2)) {
        Write-Host ("终端太矮：检测到 {0} 行，至少需要 {1} 行（游戏区 {2} 行 + 状态行 1 行）。请把窗口拉高或缩小字号后重试。" -f `
            $script:TermRows, ($fieldRows + 2), $fieldRows) -ForegroundColor Yellow
        return
    }

    Initialize-Buffers $canvasW

    # 渲染模式：auto 时逐个字符探测终端能否编码（注意 GBK 代码页没有 ▀！）
    [void](Resolve-RenderMode $Render ([bool]$Ascii))
    $script:FocusOnly = [bool]$FocusOnly
    $script:G = New-Game $canvasW
    Reset-SpeedTo $C.SPEED
    Initialize-Input

    $origCursor = $true
    try { $origCursor = [Console]::CursorVisible } catch { }
    try { [Console]::CursorVisible = $false } catch { }
    try {
        Write-Host ("渲染模式: {0}    游戏区: {1} 列 x {2} 行" -f `
            $script:RenderMode, $script:CharCols, $script:FieldRows) -ForegroundColor DarkGray
        if ($script:RenderMode -ne 'braille') {
            Write-Host ("提示: 想要最细腻的点阵效果，先在 Windows Terminal 里执行 chcp 65001 再运行本脚本（当前字符集回退为 {0}）。" -f $script:RenderMode) -ForegroundColor DarkGray
        }
        Start-Sleep -Milliseconds 1100
    } catch { }
    try { [Console]::Clear() } catch { }
    if (-not $NoColor) {
        try {
            [Console]::ForegroundColor = [ConsoleColor]::Gray
            [Console]::BackgroundColor = [ConsoleColor]::Black
        } catch { }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastLogic = 0.0
    $acc = 0.0
    $startTime = 0.0
    $quit = $false

    try {
        while (-not $quit) {
            $now = $sw.Elapsed.TotalMilliseconds
            $keys = Get-KeySnapshot
            $act = Apply-Input $keys ($now - $script:G.crashTime)
            if ($act -eq 'quit') { break }

            $acc += ($now - $lastLogic)
            $lastLogic = $now
            $steps = 0
            while (($acc -ge $C.MS_PER_FRAME) -and ($steps -lt 5)) {
                $wasCrashed = $script:G.crashed
                Step-Frame $C.MS_PER_FRAME
                if ($script:G.crashed -and -not $wasCrashed) { $script:G.crashTime = $now }
                $acc -= $C.MS_PER_FRAME
                $steps++
            }
            if ($acc -gt ($C.MS_PER_FRAME * 5)) { $acc = 0 }   # 丢弃积压，避免追帧雪崩

            if ($steps -gt 0) { Render-Frame }

            # stdout 被重定向/无真实控制台时写屏会全部失败：不要静默空转，直接说明并退出
            if ($script:RenderFail -gt 120) {
                try { [Console]::CursorVisible = $origCursor } catch { }
                Write-Host ''
                Write-Host '无法写入控制台（stdout 可能被重定向，或当前宿主不是真实终端窗口）。' -ForegroundColor Red
                Write-Host '请在真实的终端窗口里运行，例如从开始菜单打开 Windows Terminal / PowerShell。' -ForegroundColor Red
                break
            }

            try { [System.Threading.Thread]::Sleep(1) } catch { Start-Sleep -Milliseconds 2 }
        }
    } finally {
        try { [Console]::CursorVisible = $origCursor } catch { }
        if (-not $NoColor) {
            try {
                [Console]::ForegroundColor = [ConsoleColor]::Gray
                [Console]::BackgroundColor = [ConsoleColor]::Black
            } catch { }
        }
        # 退出时把游戏区擦干净，只留一行分数 —— 免得屏幕上剩一堆点阵字符
        try {
            $blank = ' ' * $script:CharCols
            for ($r = 0; $r -le $fieldRows; $r++) {
                [Console]::SetCursorPosition(0, $r)
                [Console]::Write($blank)
            }
            [Console]::SetCursorPosition(0, 0)
            [Console]::WriteLine(('本局分数: {0}   最高分: {1}' -f `
                $script:G.meter.score, $script:G.meter.highScoreStr))
            [Console]::WriteLine('')
        } catch { }
    }
}
#endregion

if ($Simulate) {
    $script:Rng = New-Object System.Random 12345      # 固定种子：自检结果可复现
    Invoke-Simulation
} elseif ($GlyphTest) {
    Invoke-GlyphTest
} elseif ($Dump) {
    Invoke-Dump
} else {
    # [void] 接住：万一哪个函数把值漏进了管道，也不会在退出时一次性打印出来
    [void](Start-GameLoop)
}
