# (C) Uri Wilensky. https://github.com/NetLogo/Tortoise

Nobody          = require('./nobody')
Observer        = require('./observer')
Patch           = require('./patch')
PatchSet        = require('./patchset')
topologyFactory = require('./topology/factory')
LinkManager     = require('./world/linkmanager')
Ticker          = require('./world/ticker')
TurtleManager   = require('./world/turtlemanager')
StrictMath      = require('shim/strictmath')
NLMath          = require('util/nlmath')
{ version }     = require('meta')

{ map, isEmpty, flatMap, filter, foldl, concat }     = require('brazierjs/array')
{ pipeline, flip }                                   = require('brazierjs/function')
{ keys, values }                                     = require('brazierjs/object')
{ isString }                                         = require('brazierjs/type')
{ TopologyInterrupt }                                = require('util/exception')

module.exports =
  class World

    # type ShapeMap = Object[Shape]

    id: 0 # Number

    breedManager:  undefined # BreedManager
    linkManager:   undefined # LinkManager
    observer:      undefined # Observer
    rng:           undefined # RNG
    selfManager:   undefined # SelfManager
    ticker:        undefined # Ticker
    topology:      undefined # Topology
    turtleManager: undefined # TurtleManager

    _patches:     undefined # Array[Patch]
    _plotManager: undefined # PlotManager
    _updater:     undefined # Updater

    # Optimization-related variables
    _patchesAllBlack:          undefined # Boolean
    _patchesWithLabels:        undefined # Number

    # (MiniWorkspace, WorldConfig, Array[String], Array[String], Array[String], Number, Number, Number, Number, Number, Boolean, Boolean, ShapeMap, ShapeMap, () => Unit) => World
    constructor: (miniWorkspace, @_config, globalNames, interfaceGlobalNames, @patchesOwnNames, minPxcor, maxPxcor, minPycor
                , maxPycor, @patchSize, wrappingAllowedInX, wrappingAllowedInY, @turtleShapeMap, @linkShapeMap
                , onTickFunction) ->
      { selfManager: @selfManager, updater: @_updater, rng: @rng
      , breedManager: @breedManager, plotManager: @_plotManager } = miniWorkspace

      @_patchesAllBlack   = true
      @_patchesWithLabels = 0

      @_updater.collectUpdates()
      @_updater.registerWorldState({
        worldWidth: maxPxcor - minPxcor + 1,
        worldHeight: maxPycor - minPycor + 1,
        minPxcor: minPxcor,
        minPycor: minPycor,
        maxPxcor: maxPxcor,
        maxPycor: maxPycor,
        linkBreeds: "XXX IMPLEMENT ME",
        linkShapeList: @linkShapeMap,
        patchSize: @patchSize,
        patchesAllBlack: @_patchesAllBlack,
        patchesWithLabels: @_patchesWithLabels,
        ticks: -1,
        turtleBreeds: "XXX IMPLEMENT ME",
        turtleShapeList: @turtleShapeMap,
        unbreededLinksAreDirected: false
        wrappingAllowedInX: wrappingAllowedInX,
        wrappingAllowedInY: wrappingAllowedInY
      })

      onTick = =>
        @rng.withAux(onTickFunction)
        @_plotManager.updatePlots()

      @linkManager   = new LinkManager(this, @breedManager, @_updater, @_setUnbreededLinksDirected, @_setUnbreededLinksUndirected)
      @observer      = new Observer(@_updater.updated, globalNames, interfaceGlobalNames)
      @ticker        = new Ticker(@_plotManager.setupPlots, onTick, @_updater.updated(this))
      @topology      = null
      @turtleManager = new TurtleManager(this, @breedManager, @_updater, @rng.nextInt)

      @_patches = []

      @_resizeHelper(minPxcor, maxPxcor, minPycor, maxPycor, wrappingAllowedInX, wrappingAllowedInY)

    # () => LinkSet
    links: ->
      @linkManager.links()

    # () => TurtleSet
    turtles: ->
      @turtleManager.turtles()

    # () => PatchSet
    patches: =>
      new PatchSet(@_patches, "patches")

    # (Number, Number, Number, Number, Boolean, Boolean) => Unit
    resize: (minPxcor, maxPxcor, minPycor, maxPycor, wrapsInX = @topology._wrapInX, wrapsInY = @topology._wrapInY) ->
      @_resizeHelper(minPxcor, maxPxcor, minPycor, maxPycor, wrapsInX, wrapsInY)
      @clearDrawing()

    # (Number, Number, Number, Number, Boolean, Boolean) => Unit
    _resizeHelper: (minPxcor, maxPxcor, minPycor, maxPycor, wrapsInX = @topology._wrapInX, wrapsInY = @topology._wrapInY) ->

      if not (minPxcor <= 0 <= maxPxcor and minPycor <= 0 <= maxPycor)
        throw new Error("You must include the point (0, 0) in the world.")

      if (minPxcor isnt @topology?.minPxcor or minPycor isnt @topology?.minPycor or
          maxPxcor isnt @topology?.maxPxcor or maxPycor isnt @topology?.maxPycor)

        @_config.resizeWorld()

        # For some reason, JVM NetLogo doesn't restart `who` ordering after `resize-world`; even the test for this is existentially confused. --JAB (4/3/14)
        @turtleManager._clearTurtlesSuspended()

        @changeTopology(wrapsInX, wrapsInY, minPxcor, maxPxcor, minPycor, maxPycor)
        @_createPatches()
        @_declarePatchesAllBlack()
        @_resetPatchLabelCount()
        @_updater.updated(this)("width", "height", "minPxcor", "minPycor", "maxPxcor", "maxPycor")

      return

    # (Boolean, Boolean, Number, Number, Number, Number) => Unit
    changeTopology: (wrapsInX, wrapsInY, minX = @topology.minPxcor, maxX = @topology.maxPxcor, minY = @topology.minPycor, maxY = @topology.maxPycor) ->
      @topology = topologyFactory(wrapsInX, wrapsInY, minX, maxX, minY, maxY, @patches, @getPatchAt)
      @_updater.updated(this)("wrappingAllowedInX", "wrappingAllowedInY")
      return

    # (Number, Number) => Agent
    getPatchAt: (x, y) =>
      try
        roundedX  = @_roundXCor(x)
        roundedY  = @_roundYCor(y)
        index     = (@topology.maxPycor - roundedY) * @topology.width + (roundedX - @topology.minPxcor)
        @_patches[index]
      catch error
        if error instanceof TopologyInterrupt
          Nobody
        else
          throw error

    # (Number, Number) => Agent
    patchAtCoords: (x, y) ->
      try
        newX = @topology.wrapX(x)
        newY = @topology.wrapY(y)
        @getPatchAt(newX, newY)
      catch error
        if error instanceof TopologyInterrupt then Nobody else throw error

    # (Number, Number, Number, Number) => Agent
    patchAtHeadingAndDistanceFrom: (angle, distance, x, y) ->
      heading = NLMath.normalizeHeading(angle)
      targetX = x + distance * NLMath.squash(NLMath.sin(heading))
      targetY = y + distance * NLMath.squash(NLMath.cos(heading))
      @patchAtCoords(targetX, targetY)

    # (Number) => Unit
    setPatchSize: (@patchSize) ->
      @_updater.updated(this)("patchSize")
      return

    # () => Unit
    clearAll: ->
      @observer.clearCodeGlobals()
      @observer.resetPerspective()
      @turtleManager.clearTurtles()
      @clearPatches()
      @clearLinks()
      @_declarePatchesAllBlack()
      @_resetPatchLabelCount()
      @ticker.clear()
      @_plotManager.clearAllPlots()
      @clearDrawing()
      return

    # () => Unit
    clearDrawing: ->
      @_updater.clearDrawing()
      return

    # () => Unit
    clearLinks: ->
      @linkManager.clear()
      @turtles().ask((-> SelfManager.self().linkManager.clear()), false)
      return

    # () => Unit
    clearPatches: ->
      @patches().forEach((patch) -> patch.reset(); return)
      @_declarePatchesAllBlack()
      @_resetPatchLabelCount()
      return

    # (Number, Number) => PatchSet
    getNeighbors: (pxcor, pycor) ->
      new PatchSet(@topology.getNeighbors(pxcor, pycor))

    # (Number, Number) => PatchSet
    getNeighbors4: (pxcor, pycor) ->
      new PatchSet(@topology.getNeighbors4(pxcor, pycor))

    # The wrapping and rounding below is setup to avoid creating extra anonymous functions.
    # We could just use @ and fat arrows => but CoffeeScript uses anon funcs to bind `this`.
    # Those anon funcs cause GC pressure and runtime slowdown, so we have to manually setup
    # the context somehow.  A lot of rounding and wrapping goes on in models.  -JMB 07/2017

    # (Number) => Number
    _thisWrapX: (x) =>
      @topology.wrapX(x)

    # (Number) => Number
    _thisWrapY: (y) =>
      @topology.wrapY(y)

    # (Number) => Number
    _roundXCor: (x) ->
      wrappedX = @_wrapC(x, @_thisWrapX)
      @_roundCoordinate(wrappedX)

    # (Number) => Number
    _roundYCor: (y) ->
      wrappedY = @_wrapC(y, @_thisWrapY)
      @_roundCoordinate(wrappedY)

    # Similarly, using try/catch as an expression creates extra anon funcs, so we get
    # this value manually as well.  -JMB 07/2017

    # (Number, (Number) => Number) => Number
    _wrapC: (c, wrapper) ->
      wrappedC = undefined
      try
        wrappedC = wrapper(c)
      catch error
        trueError =
          if error instanceof TopologyInterrupt
            new TopologyInterrupt("Cannot access patches beyond the limits of current world.")
          else
            error
        throw trueError
      wrappedC

    # Boy, oh, boy!  Headless has only this to say about this code: "floor() is slow so we
    # don't use it".  I have a lot more to say!  This code is kind of nuts, but we can't
    # live without it unless something is done about Headless' uses of `World.roundX` and
    # and `World.roundY`.  The previous Tortoise code was somewhat sensible about patch
    # boundaries, but had to be supplanted by this in order to become compliant with NL
    # Headless, which interprets `0.4999999999999999167333` as being one patch over from
    # `0` (whereas, sensically, we should only do that starting at `0.5`).  But... we
    # don't live in an ideal world, so I'll just replicate Headless' silly behavior here.
    # --JAB (12/6/14)
    # (Number) => Number
    _roundCoordinate: (wrappedC) ->
      if wrappedC > 0
        (wrappedC + 0.5) | 0
      else
        integral   = wrappedC | 0
        fractional = integral - wrappedC
        if fractional > 0.5 then integral - 1 else integral

    # () => Unit
    _createPatches: ->
      nested =
        for y in [@topology.maxPycor..@topology.minPycor]
          for x in [@topology.minPxcor..@topology.maxPxcor]
            id = (@topology.width * (@topology.maxPycor - y)) + x - @topology.minPxcor
            new Patch(id, x, y, this, @_updater.updated, @_declarePatchesNotAllBlack, @_decrementPatchLabelCount, @_incrementPatchLabelCount)

      @_patches = [].concat(nested...)

      for patch in @_patches
        @_updater.updated(patch)("pxcor", "pycor", "pcolor", "plabel", "plabel-color")

      return

    # (Number) => PatchSet
    _optimalPatchCol: (xcor) ->
      { maxPxcor: maxX, maxPycor: maxY, minPxcor: minX, minPycor: minY } = @topology
      @_optimalPatchSequence(xcor, minX, maxX, minY, maxY, (y) => @getPatchAt(xcor, y))

    # (Number) => PatchSet
    _optimalPatchRow: (ycor) ->
      { maxPxcor: maxX, maxPycor: maxY, minPxcor: minX, minPycor: minY } = @topology
      @_optimalPatchSequence(ycor, minY, maxY, minX, maxX, (x) => @getPatchAt(x, ycor))

    # (Number, Number, Number, Number, Number, (Number) => Agent) => PatchSet
    _optimalPatchSequence: (cor, boundaryMin, boundaryMax, seqStart, seqEnd, getPatch) ->
      ret =
        if boundaryMin <= cor <= boundaryMax
          [].concat(getPatch(n) for n in [seqStart..seqEnd]...)
        else
          []
      new PatchSet(ret)

    # () => Unit
    _incrementPatchLabelCount: =>
      @_setPatchLabelCount((count) -> count + 1)
      return

    # () => Unit
    _decrementPatchLabelCount: =>
      @_setPatchLabelCount((count) -> count - 1)
      return

    # () => Unit
    _resetPatchLabelCount: ->
      @_setPatchLabelCount(-> 0)
      return

    # ((Number) => Number) => Unit
    _setPatchLabelCount: (updateCountFunc) ->
      @_patchesWithLabels = updateCountFunc(@_patchesWithLabels)
      @_updater.updated(this)("patchesWithLabels")
      return

    # () => Unit
    _setUnbreededLinksDirected: =>
      @breedManager.setUnbreededLinksDirected()
      @_updater.updated(this)("unbreededLinksAreDirected")
      return

    # () => Unit
    _setUnbreededLinksUndirected: =>
      @breedManager.setUnbreededLinksUndirected()
      @_updater.updated(this)("unbreededLinksAreDirected")
      return

    # () => Unit
    _declarePatchesAllBlack: ->
      if not @_patchesAllBlack
        @_patchesAllBlack = true
        @_updater.updated(this)("patchesAllBlack")
      return

    # () => Unit
    _declarePatchesNotAllBlack: =>
      if @_patchesAllBlack
        @_patchesAllBlack = false
        @_updater.updated(this)("patchesAllBlack")
      return

    exportAgents: (agents, isThisAgentType, varArr, typeName) ->
      varList = pipeline(filter(isThisAgentType), flatMap((x) -> x.varNames), flip(concat)(varArr))(values(@breedManager.breeds()))
      filterAgent = (agent) =>
        f = (obj, agentVar) ->
          obj[agentVar] = agent.getVariable(agentVar)
          obj
        tempExport = foldl(f)({})(varList)
        if tempExport['breed']?
          if tempExport['breed'].toString() == typeName
            tempExport['breed'] = '{all-' + tempExport['breed'].toString() + '}'
          else
            tempExport['breed'] = '{breed ' + tempExport['breed'].toString() + '}'
        if typeName == 'links'
          tempExport['end1'] = tempExport['end1'].toString().replace('(', '{').replace(')', '}')
          tempExport['end2'] = tempExport['end2'].toString().replace('(', '{').replace(')', '}')
        tempExport
      map(filterAgent)(agents)

    # () => Object
    exportGlobals: ->
      directedLinksDefault = () =>
        if isEmpty(@links().toArray())
          'NEITHER'
        else if @breedManager.links()._isDirectedLinkBreed
          'DIRECTED'
        else
          'UNDIRECTED'
      tempExport = {
        minPxcor: @topology.minPxcor,
        maxPxcor: @topology.maxPxcor,
        minPycor: @topology.minPycor,
        maxPycor: @topology.maxPycor,
        perspective: @observer.getPerspectiveNum(),
        subject: @observer.subject(),
        nextIndex: @turtleManager.nextIndex(),
        directedLinks: directedLinksDefault(),
        ticks: @ticker.tickCount()
      }
      if @observer.varNames().length == 0
        tempExport
      pipeline(map((extraGlobal) => tempExport[extraGlobal] = @observer.getGlobal(extraGlobal)))(@observer.varNames().sort())
      tempExport

    # () => Object[Array[Object]]
    exportState: ->
      turtleDefaultVarArr = ['who', 'color', 'heading', 'xcor', 'ycor', 'shape', 'label', 'label-color',
        'breed', 'hidden?', 'size', 'pen-size', 'pen-mode']
      linkDefaultVarArr = ['end1', 'end2', 'color', 'label', 'label-color', 'hidden?',
        'breed', 'thickness', 'shape', 'tie-mode']
      {
        'patches': @exportAgents(@patches().toArray(), (-> false), ['pxcor', 'pycor', 'pcolor', 'plabel', 'plabel-color'], 'patches'),
        'turtles': @exportAgents(@turtleManager.turtles().toArray(), ((breed) -> not breed.isLinky()), turtleDefaultVarArr, 'turtles'),
        'links': @exportAgents(@linkManager.links().toArray(), ((breed) -> breed.isLinky()), linkDefaultVarArr, 'links'),
        'globals': @exportGlobals(),
        'randomState': @rng.exportState(),
        'plots': @_plotManager.exportState()
      }

    exportWorldAsJSON: ->
      @exportState()

    exportWorld: ->
      zip = (arrays) ->
        arrays[0].map((_, i) -> arrays.map((array) -> array[i]))
      quoteWrapVals = (str) ->
        if isString(str)
          if str[0] == '{'
            if str.length > 0
              '"' + str + '"'
            else
              '"""' + str + '"""'
          else
            '"""' + str + '"""'
        else if str?
          '"' + str + '"'
        else
          str
      quoteWrap = (str) ->
        '"' + str + '"'
      timeStamp = new Date()
      formatDate = (date) =>
        dateFormat = [
          date.getMonth() + 1,
          date.getDay(),
          date.getFullYear(),
          date.getHours(),
          date.getMinutes(),
          date.getSeconds(),
          date.getMilliseconds(),
          if date.getTimezoneOffset() > 0 then '-' else '+',
          Math.abs(date.getTimezoneOffset() / 60),
          Math.abs(date.getTimezoneOffset() % 60)
        ]
        digits = [2, 2, 4, 2, 2, 2, 3, 0, 2, 2]
        seperators = ['/', '/', ' ', ':', ':', ':', ' ', '', '', '']
        res = dateFormat.map((value, i) => value.toString().padStart(digits[i], '0') + seperators[i])
        res.join('')
      exportedState = @exportState()
      timeStampString = formatDate(timeStamp)
      replaceCamelCase = (varMap) => (label) =>
        if varMap.hasOwnProperty(label) then varMap[label] else label
      linkDefaultVars = {
        'end1': 'end1', 'end2': 'end2', 'color': 'color',
        'label': 'label', 'labelColor': 'label-color', 'isHidden': 'hidden?',
        'breed': 'breed', 'thickness': 'thickness', 'shape': 'shape',
        'tieMode': 'tie-mode'}
      turtleDefaultVars = {
        'who': 'who', 'color': 'color', 'heading': 'heading', 'xcor': 'xcor',
        'ycor': 'ycor', 'shape': 'shape', 'label': 'label', 'labelColor': 'label-color',
        'breed': 'breed', 'isHidden': 'hidden?', 'size': 'size', 'penSize': 'pen-size',
        'penMode': 'pen-mode'}
      patchDefaultVars = {
        'pxcor': 'pxcor', 'pycor': 'pycor', 'pcolor': 'pcolor', 'plabel': 'plabel', 'plabelColor': 'plabel-color'
      }
      globalDefaultVars = {
        'minPxcor': 'min-pxcor', 'minPycor': 'min-pycor', 'maxPxcor': 'max-pxcor',
        'maxPycor': 'max-pycor', 'perspective': 'perspective', 'subject': 'subject', 'directedLinks': 'directed-links',
        'ticks': 'ticks'
      }
      plotDefaultVars = {
        'xMin': 'x min', 'xMax': 'x max', 'yMin': 'y min', 'yMax': 'y max', 'isAutoplotting': 'autoplot?',
        'currentPen': 'current pen', 'isLegendOpen': 'legend open?', 'numPens': 'number of pens'
      }
      penDefaultVars = {
        'name': 'pen name', 'isPenDown': 'pen down?', 'mode': 'mode', 'interval': 'interval',
        'color': 'color', 'x': 'x'
      }
      pointDefaultVars = { 'x': 'x', 'y': 'y', 'color': 'color', 'penMode': 'pen down?' }
      csvPlot = (plot) ->
        [
          quoteWrapVals(plot['name']),
          pipeline(map(replaceCamelCase(plotDefaultVars)), map(quoteWrap))(keys(plot['vars'])).join(','),
          pipeline(map(quoteWrapVals))(values(plot['vars'])).join(','),
          '',
          pipeline(map(quoteWrap))(values(penDefaultVars)),
          map((pen) -> pipeline(map(quoteWrapVals))(values(pen['vars'])).join(','))(plot['pens']).join('\n'),
          '',
          map((pen) -> quoteWrapVals(pen['vars']['name']))(plot['pens']).join(',,,,'),
          flatMap((pen) -> map(quoteWrap)(values(pointDefaultVars)))(plot['pens']).join(','),
          pipeline(zip, map((row) -> map(map(quoteWrapVals))(row)), map((row) -> row.join(',')))(map((pen) -> map((point) -> [point['x'], point['y'], point['color'], point['penMode']])(pen['points']))(plot['pens'])).join('\n'),
          ''
        ]
      plotCSV = concat(['"EXTENSIONS"'])(pipeline(flatMap(csvPlot))(exportedState['plots']['plots']))
      exportCSV = concat(plotCSV)([
        '"export-world data (NetLogo Web ' + version + ')"',
        '"[IMPLEMENT .NLOGO]"',
        quoteWrap(timeStampString),
        '',
        quoteWrap('RANDOM STATE'),
        quoteWrap(exportedState['randomState']),
        '',
        quoteWrap('GLOBALS'),
        pipeline(map(replaceCamelCase(globalDefaultVars)), map(quoteWrap))(keys(exportedState['globals'])).join(','),
        pipeline(map(quoteWrapVals))(values(exportedState['globals'])).join(','),
        '',
        quoteWrap('TURTLES'),
        concat(pipeline(filter((breed) -> not breed.isLinky()), flatMap((x) -> x.varNames), map(quoteWrap))(values(@breedManager.breeds())))(map(quoteWrap)(values(turtleDefaultVars))).join(','),
        map((turt) -> pipeline(map(quoteWrapVals))(values(turt)).join(','))(exportedState['turtles']).join('\n'),
        '',
        quoteWrap('PATCHES'),
        pipeline(map(replaceCamelCase(patchDefaultVars)), map(quoteWrap))(keys(exportedState['patches'][0])).join(','),
        map((patch) -> pipeline(map(quoteWrapVals))(values(patch)).join(','))(exportedState['patches']).join('\n'),
        '',
        quoteWrap('LINKS'),
        concat(pipeline(filter((breed) -> breed.isLinky()), flatMap((x) -> x.varNames), map(quoteWrap))(values(@breedManager.breeds())))(map(quoteWrap)(values(linkDefaultVars))).join(','),
        if isEmpty(exportedState['links']) then '' else map((link) -> pipeline(map(quoteWrapVals))(values(link)).join(','))(exportedState['links']).join('\n') + '\n',
        '',
        quoteWrap('PLOTS'),
        if exportedState['plots']['currentPlot']? then quoteWrap(exportedState['plots']['currentPlot'].name) else quoteWrap(''),
      ])
      exportCSV.join('\n')

    # (WorldState, (Object[Any]) => Unit, (String) => Agent) => Unit
    importState: (
      {
        builtInGlobals: {
          directedLinks: directedLinks
        , maxPxcor:      maxPxcor
        , maxPycor:      maxPycor
        , minPxcor:      minPxcor
        , minPycor:      minPycor
        , nextIndex
        , perspective
        , subject
        , ticks
        }
      , links
      , patches
      , rngState
      , turtles
      , userGlobals
      }
    , reifyLinkEnds, reifySubject) ->

      @clearAll()

      @rng.importState(rngState)

      for key, value of userGlobals
        @observer.setGlobal(key, value)
      @ticker.importTicks(ticks)

      if directedLinks is "DIRECTED"
        @_setUnbreededLinksDirected()
      else
        @_setUnbreededLinksUndirected()

      @_resizeHelper(minPxcor, maxPxcor, minPycor, maxPycor, @topology._wrapInX, @topology._wrapInY)
      patches.forEach(
        (patchState) =>
          patch = @patchAtCoords(patchState.pxcor, patchState.pycor)
          for k, v of patchState when k isnt "pxcor" and k isnt "pycor"
            patch.setPatchVariable(k, v)
          return
      )

      @turtleManager.importState(turtles, nextIndex)

      reifyLinkEnds(links)
      @linkManager.importState(links)

      trueSubject = reifySubject(subject)
      if trueSubject isnt Nobody
        @observer.importState(perspective, trueSubject)

      return
