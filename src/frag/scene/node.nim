import
    events,
    basic2d,
    ../assets/asset,
    ../math/rectangle,
    ../graphics/camera,
    ../graphics/two_d/animation,
    ../graphics/two_d/spritebatch,
    ../graphics/two_d/texture_region,
    ../maps/tiled_map

type

    Node* = ref object
        scene: Scene
        parent: Node
        children: seq[Node]
        components: seq[NodeComponent]

        position: Vector2d
        layer: int

        dirty: bool
        absolutePosition: Vector2d

        name*: string

    Scene* = ref object
        rootNode: Node
        eventEmitter: EventEmitter

        # TODO: move this to a component, and add layer support
        drawables: seq[Drawable]

        Update: EventHandler

    UpdateEventArgs* = object of EventArgs
        deltaTime*: float

    NodeComponent* = ref object of RootObj
        node: Node

    RenderContext* = object
        viewbounds: Rectangle
        camera: Camera
        batch: SpriteBatch

    Drawable* = ref object of NodeComponent
        aabb: Rectangle
        aabbDirty: bool

    SpriteComponent* = ref object of Drawable
        source: TextureRegion

    AnimatedSpriteComponent* = ref object of Drawable
        source: Animation
        time: float
        playing: bool
        currentSprite: TextureRegion

        updateCallback: proc (e: EventArgs) {.closure.}

    TiledMapComponent* = ref object of Drawable
        source: TiledMap

method didAttach*(self: NodeComponent) {.base.} =
    discard

method willDetach*(self: NodeComponent) {.base.} =
    discard

method nodeMarkedDirty*(self: NodeComponent) {.base.} =
    discard

proc absolutePosition*(self: Node): Vector2d

proc markDirty(self: Node) =

    if self.dirty:
        return

    self.dirty = true

    for component in self.components:
        component.nodeMarkedDirty()

    for child in self.children:
        child.markDirty()

proc updateAbsolutePosition(self: Node) =

    if self.parent == nil:
        self.absolutePosition = self.position

    else:
        self.absolutePosition = absolutePosition(self.parent) + self.position

    self.dirty = false

proc componentDidAttach*(self: Scene, component: NodeComponent) =
    component.didAttach()

proc componentWillDetach*(self: Scene, component: NodeComponent) =
    component.willDetach()

proc nodeDidAttach*(self: Scene, node: Node) =

    node.scene = self

    for component in node.components:
        self.componentDidAttach(component)

    for child in node.children:
        self.nodeDidAttach(child)

proc nodeWillDetach*(self: Scene, node: Node) =

    for child in node.children:
        self.nodeWillDetach(child)

    for component in node.components:
        self.componentWillDetach(component)

    node.scene = nil

proc newNode*(): Node =
    return Node(
        children: @[],
        components: @[]
    )

proc newNode*(position: Vector2d): Node =
    return Node(
        children: @[],
        components: @[],
        position: position,
        dirty: true
    )

proc children*(self: Node): seq[Node] =
    return self.children

proc components*(self: Node): seq[NodeComponent] =
    return self.components

proc position*(self: Node): Vector2d =
    return self.position

proc `position=`*(self: Node, value: Vector2d) =
    self.position = value
    self.markDirty()

proc layer*(self: Node): int =
    return self.layer

proc `layer=`*(self: Node, value: int) =
    self.layer = value
    # TODO: implement layers

proc translate*(self: Node, delta: Vector2d) =
    self.position += delta
    self.markDirty()

proc absolutePosition*(self: Node): Vector2d =

    if self.dirty:
        self.updateAbsolutePosition()

    return self.absolutePosition

proc absoluteToLocal*(self: Node, point: Vector2d): Vector2d =
    return absolutePosition(self) - point

proc localToAbsolute*(self: Node, point: Vector2d): Vector2d =
    return absolutePosition(self) + point

proc removeChild*(self: Node, child: Node) =

    if child.parent != self:
        return

    if self.scene != nil:
        self.scene.nodeWillDetach(child)

    self.children.delete(self.children.find(child))
    child.parent = nil
    child.markDirty()

proc remove*(self: Node) =

    if self.parent != nil:
        self.parent.removeChild(self)

proc appendChild*(self: Node, child: Node) =

    # if it has a parent, detach first
    child.remove()

    self.children.add(child)
    child.parent = self
    child.markDirty()

    if self.scene != nil:
        self.scene.nodeDidAttach(child)

proc createChild*(self: Node): Node =
    let child = newNode()
    self.appendChild(child)
    return child

proc addComponent*(self: Node, component: NodeComponent) =
    self.components.add(component)
    component.node = self

    if self.scene != nil:
        self.scene.componentDidAttach(component)

proc newScene*(eventEmitter: EventEmitter): Scene =

    let scene = Scene(
        rootNode: newNode(),
        eventEmitter: eventEmitter,

        drawables: @[],

        Update: initEventHandler("Update")
    )

    scene.rootNode.scene = scene
    return scene

proc rootNode*(self: Scene): Node =
    return self.rootNode

proc eventEmitter*(self: Scene): EventEmitter =
    return self.eventEmitter

proc update*(self: Scene, deltaTime: float) =

    self.eventEmitter.emit(self.Update, UpdateEventArgs(
        deltaTime: deltaTime
    ))

method render*(self: Drawable, context: RenderContext) {.base.} =
    discard

proc node*(self: NodeComponent): Node =
    return self.node

proc scene*(self: NodeComponent): Scene =

    if self.node == nil:
        return nil

    return self.node.scene

method calcAabb*(self: Drawable): Rectangle {.base.} =
    discard

proc markAabbDirty*(self: Drawable) =
    self.aabbDirty = true

proc updateAabb(self: Drawable) =
    self.aabbDirty = false
    self.aabb = self.calcAabb()

    let offset = absolutePosition(self.node)
    self.aabb.translate(offset.x, offset.y)

proc drawableDidAttach*(self: Drawable) =
    self.markAabbDirty()
    self.scene.drawables.add(self)

proc drawableWillDetach*(self: Drawable) =
    self.scene.drawables.delete(self.scene.drawables.find(self))

method didAttach*(self: Drawable) =
    self.drawableDidAttach()

method willDetach*(self: Drawable) =
    self.drawableWillDetach()

method nodeMarkedDirty*(self: Drawable) =
    self.markAabbDirty()

proc aabb*(self: Drawable): Rectangle =

    if self.aabbDirty:
        self.updateAabb()

    return self.aabb

proc render*(self: Scene, batch: SpriteBatch, camera: Camera) =

    # TODO: calculate the visible area
    let viewbounds = Rectangle(x: 0, y: 0, width: 960, height: 540)

    for drawable in self.drawables:

        if aabb(drawable).intersects(viewbounds):

            # the drawable is inside the view frustum
            drawable.render(RenderContext(batch: batch, viewbounds: viewbounds, camera: camera))

proc newSpriteComponent*(): SpriteComponent =
    return SpriteComponent()

proc source*(self: SpriteComponent): TextureRegion =
    return self.source

proc `source=`*(self: SpriteComponent, value: TextureRegion) =
    self.source = value
    self.markAabbDirty()

method calcAabb*(self: SpriteComponent): Rectangle =

    if self.source == nil:
        return

    return Rectangle(
        x: 0, y: 0,
        width: float self.source.regionWidth,
        height: float self.source.regionHeight
    )

method render*(self: SpriteComponent, context: RenderContext) =

    if self.source == nil:
        return

    let position = absolutePosition(self.node)

    context.batch.drawRegion(self.source, position.x, position.y)

proc newTiledMapComponent*(): TiledMapComponent =
    return TiledMapComponent()

proc source*(self: TiledMapComponent): TiledMap =
    return self.source

proc `source=`*(self: TiledMapComponent, value: TiledMap) =
    self.source = value
    self.markAabbDirty()

method calcAabb*(self: TiledMapComponent): Rectangle =

    if self.source == nil:
        return

    # TODO: calculate the TiledMap bounding box

    return Rectangle(
        x: 0, y: 0,
        width: 1000,
        height: 1000
    )

method render*(self: TiledMapComponent, context: RenderContext) =

    if self.source == nil:
        return

    let position = absolutePosition(self.node)

    context.batch.`end`()

    # TODO: translate the map rendering to the node absolute position
    self.source.render(context.batch, context.camera)

    context.batch.begin()

proc newAnimatedSpriteComponent*(): AnimatedSpriteComponent =
    return AnimatedSpriteComponent()

proc hasSource(self: AnimatedSpriteComponent): bool =
    return len(self.source.frames) > 0

proc updateCurrentSprite(self: AnimatedSpriteComponent) =

    let next = if self.hasSource: self.source.getFrame(self.time) else: nil

    if self.currentSprite != next:
        self.currentSprite = next
        self.markAabbDirty()

proc reset*(self: AnimatedSpriteComponent) =
    self.time = 0
    self.updateCurrentSprite()

proc advance(self: AnimatedSpriteComponent, deltaTime: float) =
    self.time += deltaTime
    self.updateCurrentSprite()

proc play*(self: AnimatedSpriteComponent) =
    self.playing = true

proc play*(self: AnimatedSpriteComponent, value: Animation) =
    self.source = value
    self.playing = true
    self.reset()

proc pause*(self: AnimatedSpriteComponent) =
    self.playing = false

proc source*(self: AnimatedSpriteComponent): Animation =
    return self.source

proc `source=`*(self: AnimatedSpriteComponent, value: Animation) =
    self.source = value
    self.reset()

method didAttach*(self: AnimatedSpriteComponent) =

    proc onUpdate(e: EventArgs) =

        if self.playing: 
            self.advance(UpdateEventArgs(e).deltaTime)

    self.updateCallback = onUpdate
    self.scene.Update.addHandler(onUpdate)

    # call common Drawable implementation
    drawableDidAttach(self)

method willDetach*(self: AnimatedSpriteComponent) =

    # call common Drawable implementation
    self.drawableWillDetach()

    self.scene.Update.removeHandler(self.updateCallback)

method calcAabb*(self: AnimatedSpriteComponent): Rectangle =

    if self.currentSprite == nil:
        return

    return Rectangle(
        x: 0, y: 0,
        width: float self.currentSprite.regionWidth,
        height: float self.currentSprite.regionHeight
    )

method render*(self: AnimatedSpriteComponent, context: RenderContext) =

    if self.currentSprite == nil:
        return

    let position = absolutePosition(self.node)

    context.batch.drawRegion(self.currentSprite, position.x, position.y)
