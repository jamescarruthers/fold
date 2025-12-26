# Three.js WebGL-based viewer for FOLD files
# Requires Three.js to be loaded via script tag (includes OrbitControls)
viewer3 = exports

# Colors matching the SVG viewer styles
COLORS =
  top: 0x00ffff      # cyan - front face
  bot: 0xffff00      # yellow - back face
  B: 0x000000        # black - boundary
  M: 0xff0000        # red - mountain
  V: 0x0000ff        # blue - valley
  U: 0x888888        # gray - unassigned
  F: 0x888888        # gray - flat

# Default visibility settings
DEFAULTS =
  show:
    Faces: true
    Edges: true
    Vertices: false

### UTILITIES ###

viewer3.appendHTML = (el, tag, attrs) ->
  child = document.createElement(tag)
  child.setAttribute(k, v) for k, v of attrs if attrs?
  el.appendChild(child)

### INTERFACE ###

viewer3.addViewer = (div, opts = {}) ->
  THREE = window.THREE
  unless THREE?
    throw new Error('Three.js must be loaded before using viewer3')

  view = { opts: opts, THREE: THREE }
  view.show = {}
  view.show[k] = v for k, v of DEFAULTS.show

  # Get container dimensions
  width = opts.width ? 600
  height = opts.height ? 600

  # Create toggle UI
  toggleDiv = viewer3.appendHTML(div, 'div', { style: 'margin-bottom: 5px;' })
  toggleDiv.innerHTML = 'Toggle: '
  for name of view.show
    checkbox = viewer3.appendHTML(toggleDiv, 'input', {
      type: 'checkbox', value: name, id: "toggle-#{name}"
    })
    checkbox.checked = view.show[name]
    label = viewer3.appendHTML(toggleDiv, 'label', { for: "toggle-#{name}" })
    label.innerHTML = "#{name} "
    checkbox.onchange = do (name) -> (e) ->
      view.show[name] = e.target.checked
      viewer3.updateVisibility(view)

  # Create scene
  view.scene = new THREE.Scene()
  view.scene.background = new THREE.Color(0xffffff)

  # Create orthographic camera
  aspect = width / height
  frustumSize = 2
  view.camera = new THREE.OrthographicCamera(
    -frustumSize * aspect / 2, frustumSize * aspect / 2,
    frustumSize / 2, -frustumSize / 2,
    0.1, 1000
  )
  view.camera.position.set(0, 0, 5)
  view.camera.lookAt(0, 0, 0)

  # Create renderer
  view.renderer = new THREE.WebGLRenderer({ antialias: true })
  view.renderer.setSize(width, height)
  view.renderer.setPixelRatio(window.devicePixelRatio)
  div.appendChild(view.renderer.domElement)

  # Add orbit controls (from Three.js examples)
  OrbitControls = THREE.OrbitControls
  if OrbitControls?
    view.controls = new OrbitControls(view.camera, view.renderer.domElement)
    view.controls.enableDamping = true
    view.controls.dampingFactor = 0.05
    view.controls.enablePan = true
    view.controls.enableZoom = true
  else
    console.warn('OrbitControls not found. Mouse controls disabled.')
    view.controls = { update: -> }

  # Animation loop
  animate = ->
    requestAnimationFrame(animate)
    view.controls.update()
    view.renderer.render(view.scene, view.camera)
  animate()

  view

viewer3.updateVisibility = (view) ->
  return unless view.model?
  view.facesGroup?.visible = view.show.Faces
  view.edgesGroup?.visible = view.show.Edges
  view.verticesGroup?.visible = view.show.Vertices

viewer3.processInput = (input, view) ->
  THREE = view.THREE

  # Parse input
  if typeof input is 'string'
    view.fold = JSON.parse(input)
  else
    view.fold = input

  # Clear existing model
  if view.model?
    view.scene.remove(view.model)

  # Create new model group
  view.model = new THREE.Group()
  view.facesGroup = new THREE.Group()
  view.edgesGroup = new THREE.Group()
  view.verticesGroup = new THREE.Group()
  view.model.add(view.facesGroup)
  view.model.add(view.edgesGroup)
  view.model.add(view.verticesGroup)

  # Build geometry
  vertices = view.fold.vertices_coords
  faces = view.fold.faces_vertices
  edges = view.fold.edges_vertices
  edgeAssignments = view.fold.edges_assignment

  # Ensure 3D coordinates
  vertices = for v in vertices
    if v.length is 2 then [v[0], v[1], 0] else v

  # Calculate bounding box for centering
  min = [Infinity, Infinity, Infinity]
  max = [-Infinity, -Infinity, -Infinity]
  for v in vertices
    for i in [0, 1, 2]
      min[i] = Math.min(min[i], v[i])
      max[i] = Math.max(max[i], v[i])

  center = [(min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2]
  modelScale = Math.max(max[0] - min[0], max[1] - min[1], max[2] - min[2])
  modelScale = 1.8 / modelScale if modelScale > 0

  # Store transformed vertices for reuse
  transformedVerts = for v in vertices
    [
      (v[0] - center[0]) * modelScale
      (v[1] - center[1]) * modelScale
      (v[2] - center[2]) * modelScale
    ]

  # Create face geometry
  if faces?
    # Build indexed geometry
    geometry = new THREE.BufferGeometry()

    # Flatten vertices
    positions = []
    for v in transformedVerts
      positions.push(v[0], v[1], v[2])

    geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))

    # Triangulate faces (simple fan triangulation)
    indices = []
    for face in faces
      if face.length >= 3
        for i in [1...face.length - 1]
          indices.push(face[0], face[i], face[i + 1])

    geometry.setIndex(indices)
    geometry.computeVertexNormals()

    # Front face mesh (cyan)
    frontMaterial = new THREE.MeshBasicMaterial({
      color: COLORS.top
      side: THREE.FrontSide
      transparent: true
      opacity: 0.8
      polygonOffset: true
      polygonOffsetFactor: 1
      polygonOffsetUnits: 1
    })
    frontMesh = new THREE.Mesh(geometry, frontMaterial)
    view.facesGroup.add(frontMesh)

    # Back face mesh (yellow)
    backMaterial = new THREE.MeshBasicMaterial({
      color: COLORS.bot
      side: THREE.BackSide
      transparent: true
      opacity: 0.8
      polygonOffset: true
      polygonOffsetFactor: 1
      polygonOffsetUnits: 1
    })
    backMesh = new THREE.Mesh(geometry.clone(), backMaterial)
    view.facesGroup.add(backMesh)

  # Create edge geometry
  if edges?
    # Group edges by assignment type
    edgesByType = {}
    for edge, i in edges
      assignment = edgeAssignments?[i] ? 'U'
      edgesByType[assignment] ?= []
      edgesByType[assignment].push(edge)

    # Create line segments for each type
    for type, typeEdges of edgesByType
      linePositions = []
      for edge in typeEdges
        v1 = transformedVerts[edge[0]]
        v2 = transformedVerts[edge[1]]
        linePositions.push(v1[0], v1[1], v1[2], v2[0], v2[1], v2[2])

      lineGeometry = new THREE.BufferGeometry()
      lineGeometry.setAttribute('position', new THREE.Float32BufferAttribute(linePositions, 3))

      lineMaterial = new THREE.LineBasicMaterial({
        color: COLORS[type] ? COLORS.U
        linewidth: 1
      })

      lines = new THREE.LineSegments(lineGeometry, lineMaterial)
      view.edgesGroup.add(lines)

  # Create vertex geometry (small spheres)
  if vertices?
    vertexGeometry = new THREE.SphereGeometry(0.008, 6, 6)
    vertexMaterial = new THREE.MeshBasicMaterial({ color: 0xffffff })
    vertexOutlineMaterial = new THREE.MeshBasicMaterial({ color: 0x000000, side: THREE.BackSide })

    for v in transformedVerts
      # White sphere
      sphere = new THREE.Mesh(vertexGeometry, vertexMaterial)
      sphere.position.set(v[0], v[1], v[2])
      view.verticesGroup.add(sphere)

      # Black outline (slightly larger back-face sphere)
      outline = new THREE.Mesh(vertexGeometry, vertexOutlineMaterial)
      outline.position.set(v[0], v[1], v[2])
      outline.scale.setScalar(1.4)
      view.verticesGroup.add(outline)

  view.scene.add(view.model)

  # Apply initial visibility
  viewer3.updateVisibility(view)

  view

viewer3.importURL = (url, view) ->
  fetch(url)
    .then((response) -> response.text())
    .then((text) -> viewer3.processInput(text, view))
    .catch((err) -> console.error('Error loading FOLD file:', err))

viewer3.importFile = (file, view) ->
  reader = new FileReader()
  reader.onload = (e) -> viewer3.processInput(e.target.result, view)
  reader.readAsText(file)
