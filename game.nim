import sdl2, sdl2/ttf, basic2d, times, json, colors, os, strutils

# Types
type
  SDLException = object of IOError

  Input {.pure.} = enum none, left, right, up, down, restart, quit

  Vec2 = object
    x: cint
    y: cint

  Player = ref object
    size: Vector2d
    pos: Point2d
    vel: Vector2d
    jumping: bool
    time: Time

  Block = ref object
    size: Vector2d
    pos: Point2d
    fill: colors.Color

  Level = ref object
    id: int
    title: string
    spawn: Point2d
    blocks: seq[Block]
    
  Button = ref object
    id: int
    label: string
    pos: Point2d
    size: Vector2d

  Game = ref object
    inputs: array[Input, bool]
    mouse: Vec2
    renderer: RendererPtr
    player: Player
    level: Level
    levels: seq[string]
    camera: Vector2d
    active: bool
    fonts: seq[FontPtr]
    buttons: seq[Button]


template sdlFailIf(cond: typed, reason: string) =
  if cond: raise SDLException.newException(
    reason & ", SDL error: " & $getError())

# Procedures

proc renderButton (renderer: RendererPtr, button: Button) =
      var rect: Rect = (
          x: cint(button.pos.x),
          y: cint(button.pos.y),
          w: cint(button.size.x),
          h: cint(button.size.y)
      )
      renderer.setDrawColor(255,0,0,255)
      renderer.fillRect(rect)

proc renderText(renderer: RendererPtr, font: FontPtr, text: string,
                x, y: cint, color: sdl2.Color) =
  let surface = font.renderUtf8Blended(text.cstring, color)
  sdlFailIf surface.isNil: "Could not render text surface"

  discard surface.setSurfaceAlphaMod(color.a)

  var source = rect(0, 0, surface.w, surface.h)
  var dest = rect(x, y, surface.w, surface.h)
  let texture = renderer.createTextureFromSurface(surface)

  sdlFailIf texture.isNil:
    "Could not create texture from rendered text"

  surface.freeSurface()

  renderer.copyEx(texture, source, dest, angle = 0.0, center = nil,
                  flip = SDL_FLIP_NONE)

  texture.destroy()

proc renderText(game: Game, font: FontPtr, text: string, x, y: cint, color: sdl2.Color) =
  game.renderer.renderText(font, text, x, y, color)
  
proc newPlayer(): Player =
  new result
  result.size = vector2d(32, 32)
  result.vel = vector2d(0, 0)
  result.jumping = false


proc getLevels(): seq = 
  var arr = newSeq[string]()
  for path in walkFiles("levels/*.json"):
    var s = path
    s.removePrefix("levels/")
    s.removeSuffix(".json")
    arr.add(s)
  result = arr

proc loadFonts(): seq[FontPtr] =
  # define fonts
  var sourceSm = openFont("SourceSansProBold.ttf", 24)
  var sourceMd = openFont("SourceSansProBold.ttf", 32)
  var sourceLg = openFont("SourceSansProBold.ttf", 48)
  var emoji = openFont("NotoColorEmoji.ttf", 32)

  # If the fonts fail to load
  sdlFailIf sourceSm.isNil: "Failed to load font"
  sdlFailIf sourceMd.isNil: "Failed to load font"
  sdlFailIf sourceLg.isNil: "Failed to load font"
  sdlFailIf emoji.isNil: "Failed to load font"

  # Add fonts
  result.add(sourceSm)
  result.add(sourceMd)
  result.add(sourceLg)
  result.add(emoji)

proc loadLevel(): Level =
  var data = json.parseFile("levels/testA.json")
  var lev = Level()

  lev.blocks = newSeq[Block]()
  lev.id = 1
  lev.title = "Test Level"
  lev.spawn = point2d(
      100,
      100
  )

  for layer in data["layers"]:
    if layer["name"].str == "Platform":
      for obj in layer["objects"]:
        var b = Block()
        b.size = vector2d(
          obj["width"].getFloat,
          obj["height"].getFloat
        )
        b.pos = point2d(
          obj["x"].getFloat,
          obj["y"].getFloat
        )
        if obj.contains("properties"):
          for prop in obj["properties"]:
            if prop["name"].str == "fill":
              var fill = prop["value"].str
              b.fill = parseColor(fill)
        else:
          b.fill = parseColor("#CCCCCC")
        lev.blocks.add(b)
    elif layer["name"].str == "Spawn":
      lev.spawn = point2d(
        layer["objects"][0]["x"].getFloat,
        layer["objects"][0]["y"].getFloat
      )


#[  for i in data["blocks"]:
    var b = Block()
    b.size = vector2d(
      i["width"].getFloat,
      i["height"].getFloat
    )
    b.pos = point2d(
      i["x"].getFloat,
      i["y"].getFloat
    )
    b.fill = parseColor(i["fill"].str)
    lev.blocks.add(b)
]#
  result = lev

proc createButtons (game: Game): seq[Button] =
    var arr = newSeq[Button]()

    var buttonA = Button()
    buttonA.id = 1
    buttonA.label = "Start Level"
    buttonA.pos = point2d(100,100)
    buttonA.size = vector2d(140,80)

    arr.add(buttonA)

    result = arr

proc newGame(renderer: RendererPtr): Game =
  new result
  result.renderer = renderer
  result.player = newPlayer()
  result.level = loadLevel()
  result.levels = getLevels()
  result.fonts = loadFonts()
  result.buttons = result.createButtons()

  result.player.pos = result.level.spawn

proc toInput(key: Scancode): Input =
  case key
  of SDL_SCANCODE_A: Input.left
  of SDL_SCANCODE_D: Input.right
  of SDL_SCANCODE_W: Input.up
  of SDL_SCANCODE_S: Input.down
  of SDL_SCANCODE_R: Input.restart
  of SDL_SCANCODE_Q: Input.quit
  else: Input.none

proc mouseDown(game: Game) =

  echo game.mouse

proc handleInput(game: Game) =
  var event = defaultEvent
  while pollEvent(event):
    case event.kind
    of QuitEvent:
      game.inputs[Input.quit] = true
    of KeyDown:
      game.inputs[event.key.keysym.scancode.toInput] = true
    of KeyUp:
      game.inputs[event.key.keysym.scancode.toInput] = false
    of MouseButtonDown:
      var b = event.button.button
      if b == 1:
        game.mouseDown()
    of MouseMotion:
      var v = Vec2()
      v.x = event.evMouseMotion.x
      v.y = event.evMouseMotion.y
      game.mouse = v
    else:
      discard

proc drawPlayer(game: Game) = 
  var rect: Rect = (
      x: cint(game.player.pos.x),
      y: cint(game.player.pos.y),
      w: cint(game.player.size.x),
      h: cint(game.player.size.y)
  )
  game.renderer.setDrawColor(255, 128, 128, 0)
  game.renderer.fillRect(rect.addr)

proc drawBlock (b: Block): Rect =
  var rect: Rect = (
      x: cint(b.pos.x),
      y: cint(b.pos.y),
      w: cint(b.size.x),
      h: cint(b.size.y)
  )
  result = rect

proc rectcollide(player: Player, rect: Block): bool =
      (player.pos.x + player.size.x) < rect.pos.x or
      player.pos.x > (rect.pos.x + rect.size.x) or 
      (player.pos.y + player.size.y) < rect.pos.y or
      player.pos.y > (rect.pos.y + rect.size.y)

proc smallestIndex(arr: openArray[int]): int =
  if arr.len < 1:
    return -1

  for i in countdown(arr.len - 1, 0):
    if arr[i] < arr[result]:
      result = i

proc align(player: Player, rect: Block) =
  var pos = [
    int(abs(player.pos.y + player.size.y - rect.pos.y)),
    int(abs(rect.pos.x + rect.size.x - player.pos.x)),
    int(abs(rect.pos.y + rect.size.y - player.pos.y)),
    int(abs(player.pos.x + player.size.x - rect.pos.x))
  ]

  case smallestIndex(pos)
    of 0:
      player.jumping = false
      player.pos.y = rect.pos.y - player.size.y
      player.vel.y = 0
      player.vel.x = player.vel.x * 0.96
    of 1:
      player.pos.x = rect.pos.x + rect.size.x
      player.vel.x = 0
    of 2:
      player.pos.y = rect.pos.y + rect.size.y
      player.vel.y = -(player.vel.y * 0.1)
    of 3:
      player.pos.x = rect.pos.x - player.size.x;
      player.vel.x = 0
    else:
      return

proc containsPointer (game: Game, rect: Rect): bool =
  result = rect.x <= game.mouse.x and game.mouse.x <= rect.x + rect.w and
           rect.y <= game.mouse.y and game.mouse.y <= rect.y + rect.h

proc mainScene (game: Game, renderer: RendererPTR) =
  renderer.setDrawColor(0, 0, 0, 255)
  renderer.clear()
  const white = color(255, 255, 255, 255)
  const black = color(0, 0, 0, 255)
  const red = color(255, 0, 0, 255)
  # const flicker = [white, white, white, white, white, white, black]
  # var multicolor = color(rand(255), rand(255), rand(255), 255)
  # var r = rand(flicker.len - 1)

  game.renderText(game.fonts[3], "⛰️", 20, 56, white)
  game.renderText(game.fonts[2], "PLATFORMER", 160, 70, white)
  game.renderText(game.fonts[1], "________________________", 160, 110, white)
  game.renderText(game.fonts[0], "SELECT LEVEL", 160, 150, white)

  for button in game.buttons:
    renderer.renderButton(button)

    var bbox: Rect = (
      x: cint(button.pos.x),
      y: cint(button.pos.y),
      w: cint(button.size.x),
      h: cint(button.size.y)
    )
    
    if game.containsPointer(bbox):
      game.renderText(game.fonts[0], button.label, cint(button.pos.x), cint(button.pos.y), white)
    else:
      game.renderText(game.fonts[0], button.label, cint(button.pos.x), cint(button.pos.y), black)
  
  var idx = 0
  for l in game.levels:
    idx.inc()
    game.renderText(game.fonts[0], l, 50, cint(170 + (idx * 30)), red)

proc render(game: Game) =
  if game.active == false:
    game.mainScene(game.renderer)
  else:
    game.renderer.setDrawColor(0, 0, 0, 255)
    game.renderer.clear()
    
    for i in countdown(game.level.blocks.len - 1, 0):
      var c = extractRGB(game.level.blocks[i].fill)

      game.renderer.setDrawColor(
        uint8(c.r),
        uint8(c.g),
        uint8(c.b),
        255
      )
      var blockAddr = drawBlock(game.level.blocks[i])
      game.renderer.fillRect(blockAddr.addr)

    game.drawPlayer()

  game.renderer.present()

proc physics(game: Game) =
  if game.inputs[Input.restart]:
    game.player.pos = game.level.spawn
    game.player.vel = vector2d(0,0)

  if game.inputs[Input.right]:
    game.player.vel.x = game.player.vel.x + 1
  
  if game.inputs[Input.left]:
    game.player.vel.x = game.player.vel.x - 1

  if game.inputs[Input.up] and game.player.jumping == false:
    game.player.jumping = true
    game.player.vel.y = -6

  # if game.inputs[Input.down]:
    # game.player.vel.y = game.player.vel.y + 1

  game.player.vel.x *= 0.8
  game.player.vel.y += 0.3

  game.player.pos.x += game.player.vel.x
  game.player.pos.y += game.player.vel.y

proc blockLogic(game: Game) =
  for i in countdown(game.level.blocks.len - 1, 0):
    if (rectcollide(game.player, game.level.blocks[i]) == false):
      align(game.player, game.level.blocks[i])

proc main =
  sdlFailIf(not sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS)):
    "SDL2 initialization failed"
  defer: sdl2.quit()

  sdlFailIf(not setHint("SDL_RENDER_SCALE_QUALITY", "2")):
    "Linear texture filtering could not be enabled"

  sdlFailIf(ttfInit() == SdlError): "SDL2 TTF initialization failed"
  defer: ttfQuit()

  let window = createWindow(title = "notplatformer",
    x = SDL_WINDOWPOS_CENTERED, y = SDL_WINDOWPOS_CENTERED,
    w = 800, h = 600, flags = SDL_WINDOW_SHOWN)
  sdlFailIf window.isNil: "Window could not be created"
  defer: window.destroy()
  

  let renderer = window.createRenderer(index = -1,
    flags = Renderer_PresentVsync)
  sdlFailIf renderer.isNil: "Renderer could not be created"
  defer: renderer.destroy()

  


  # Init game & renderer
  var
    game = newGame(renderer)
    startTime = epochTime()
    lastTick = 0
    

  # Game loop
  while not game.inputs[Input.quit]:
    game.handleInput()
    let newTick = int((epochTime() - startTime) * 50)
    for tick in lastTick+1 .. newTick:
      game.physics()
      game.blockLogic()
    lastTick = newTick
    game.render()

main()