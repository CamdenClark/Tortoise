# (C) Uri Wilensky. https://github.com/NetLogo/Tortoise

class WorldConfig
  # (() => Unit) => WorldConfig
  constructor: (@resizeWorld = (->)) ->

class FileReaderConfig
  # ((String) => String) => FileReaderConfig
  constructor: (@read = (->)) ->

Dump             = require('./dump')
Hasher           = require('./hasher')
readNetLogoValue = require('./readnetlogovalue')
Updater          = require('./updater')
BreedManager     = require('./core/breedmanager')
World            = require('./core/world')
SelfManager      = require('./core/structure/selfmanager')
PlotManager      = require('./plot/plotmanager')
LayoutManager    = require('./prim/layoutmanager')
LinkPrims        = require('./prim/linkprims')
ListPrims        = require('./prim/listprims')
Prims            = require('./prim/prims')
SelfPrims        = require('./prim/selfprims')
convertCSV       = require('util/worldcsvtojson')
RNG              = require('util/rng')
Timer            = require('util/timer')

{ concat, forEach } = require('brazierjs/array')
{ flip, pipeline  } = require('brazierjs/function')
{ pairs           } = require('brazierjs/object')

{ Config: ExportConfig,     Prims: ExportPrims }     = require('./prim/exportprims')
{ Config: MouseConfig,      Prims: MousePrims }      = require('./prim/mouseprims')
{ Config: OutputConfig,     Prims: OutputPrims }     = require('./prim/outputprims')
{ Config: PrintConfig,      Prims: PrintPrims }      = require('./prim/printprims')
{ Config: UserDialogConfig, Prims: UserDialogPrims } = require('./prim/userdialogprims')

class MiniWorkspace
  # (SelfManager, Updater, BreedManager, RNG, PlotManager) => MiniWorkspace
  constructor: (@selfManager, @updater, @breedManager, @rng, @plotManager) ->

module.exports =
  (modelConfig) -> (breedObjs) -> (turtlesOwns, linksOwns) -> () -> # World args; see constructor for `World` --JAB (4/17/14)

    worldArgs = arguments # If you want `Workspace` to take more parameters--parameters not related to `World`--just keep returning new functions

    dialogConfig  = modelConfig?.dialog     ? new UserDialogConfig
    exportConfig  = modelConfig?.exporting  ? new ExportConfig
    fileReader    = modelConfig?.fileReader ? new FileReaderConfig
    mouseConfig   = modelConfig?.mouse      ? new MouseConfig
    outputConfig  = modelConfig?.output     ? new OutputConfig
    plots         = modelConfig?.plots      ? []
    printConfig   = modelConfig?.print      ? new PrintConfig
    worldConfig   = modelConfig?.world      ? new WorldConfig

    rng         = new RNG

    selfManager  = new SelfManager
    breedManager = new BreedManager(breedObjs, turtlesOwns, linksOwns)
    plotManager  = new PlotManager(plots)
    prims        = new Prims(Dump, Hasher, rng)
    selfPrims    = new SelfPrims(selfManager.self)
    timer        = new Timer
    updater      = new Updater

    world           = new World(new MiniWorkspace(selfManager, updater, breedManager, rng, plotManager), worldConfig, worldArgs...)
    layoutManager   = new LayoutManager(world, rng.nextDouble)

    linkPrims       = new LinkPrims(world)
    listPrims       = new ListPrims(Hasher, prims.equality.bind(prims), rng.nextInt)

    exportPrims     = new ExportPrims(exportConfig)
    mousePrims      = new MousePrims(mouseConfig)
    outputPrims     = new OutputPrims(outputConfig, Dump)
    printPrims      = new PrintPrims(printConfig, Dump)
    userDialogPrims = new UserDialogPrims(dialogConfig)

    readFromString =
      readNetLogoValue(
        world.turtleManager.getTurtleOfBreed.bind(world.turtleManager)
      , world.getPatchAt.bind(world)
      , world.linkManager.getLink.bind(world.linkManager)
      , breedManager.get.bind(breedManager)
      , breedManager.getSingular.bind(breedManager)
      )

    # There's something funky going on here, for sure.  You might wonder why we have to run `readFromString` at such weird times.
    # Well, it's a bit tricky, actually.  Imagine, however, that we have an `export-world` file where `turtle 0` has `turtle 1` as its
    # label, and vice versa.  If we try to reify the values up front, we'll fail to retrieve both turtles, since no turtles have actually
    # been imported into the world yet.  If we try to reify them when we create the turtles, we'll run into a problem where the first one
    # instantiated won't have its label's turtle instantiated yet.  So we need to run this after the rest of the world has been set up. --JAB (4/6/17)
    importWorld = (filepath) ->

      csvText    = fileReader.read(filepath)
      worldState = convertCSV(csvText)
      { links, patches, plots, output, turtles } = worldState

      # We can safely do breeds beforehand, but not labels or variables or link ends --JAB (4/6/17)
      for turtle in turtles
        turtle.breed = readFromString(turtle.breed)

      for link in links
        link.breed = readFromString(link.breed)

      reifyLinkEnds = (linkState) ->
        for link in linkState
          link.end1 = readFromString(link.end1)
          link.end2 = readFromString(link.end2)
        return

      world.importState(worldState, reifyLinkEnds, readFromString)

      finishImportFor = (agents, lookup, genExtras) ->
        for agent in agents
          trueAgent = lookup(agent)
          pipeline(pairs, flip(concat)(genExtras(agent)), forEach(([key, value]) -> trueAgent.setVariable(key, readFromString(value))))(agent.extraVars)
        return

      finishImportFor(turtles, (({ who               }) -> world.turtleManager.getTurtle(who)                     ), (({  label }) -> [[ 'label',  label]]))
      finishImportFor(patches, (({ pxcor, pycor      }) -> world.getPatchAt(pxcor, pycor)                         ), (({ plabel }) -> [['plabel', plabel]]))
      finishImportFor(  links, (({ end1, end2, breed }) -> world.linkManager.getLink(end1.id, end2.id, breed.name)), (({  label }) -> [[ 'label',  label]]))

      plotManager.importState(plots)

      if output?
        outputConfig.write(output)

    {
      selfManager
      breedManager
      exportPrims
      layoutManager
      linkPrims
      listPrims
      mousePrims
      outputPrims
      plotManager
      prims
      printPrims
      rng
      selfPrims
      timer
      updater
      userDialogPrims
      world
      importWorld
    }
