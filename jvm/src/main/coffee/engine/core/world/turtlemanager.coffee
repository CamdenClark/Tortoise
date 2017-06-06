# (C) Uri Wilensky. https://github.com/NetLogo/Tortoise

ColorModel = require('engine/core/colormodel')
Nobody     = require('../nobody')
Turtle     = require('../turtle')
TurtleSet  = require('../turtleset')
Builtins   = require('../structure/builtins')
IDManager  = require('./idmanager')

{ map, concat, unique }        = require('brazierjs/array')
{ pipeline }   = require('brazierjs/function')
{ rangeUntil } = require('brazierjs/number')

{ DeathInterrupt, ignoring }  = require('util/exception')

ignorantly = ignoring(DeathInterrupt)

module.exports =
  class TurtleManager

    _idManager:   undefined # IDManager
    _turtles:     undefined # Array[Turtle]
    _turtlesById: undefined # Object[Number, Turtle]

    # (World, Updater, BreedManager, (Number) => Number) => TurtleManager
    constructor: (@_world, @_breedManager, @_updater, @_nextInt) ->
      @_idManager   = new IDManager
      @_turtles     = []
      @_turtlesById = {}

    # () => Unit
    clearTurtles: ->
      @turtles().forEach((turtle) -> ignorantly(() => turtle.die()))
      @_idManager.reset()
      return

    # (Number, String) => TurtleSet
    createOrderedTurtles: (n, breedName) ->
      num     = if n >= 0 then n else 0
      turtles = map(
        (index) =>
          color   = ColorModel.nthColor(index)
          heading = (360 * index) / num
          @_createNewTurtle(color, heading, 0, 0, @_breedManager.get(breedName))
      )(rangeUntil(0)(num))
      new TurtleSet(turtles)

    # (Number, String, Number, Number) => TurtleSet
    createTurtles: (n, breedName, xcor = 0, ycor = 0) ->
      num     = if n >= 0 then n else 0
      turtles = map(=>
        color   = ColorModel.randomColor(@_nextInt)
        heading = @_nextInt(360)
        @_createNewTurtle(color, heading, xcor, ycor, @_breedManager.get(breedName))
      )(rangeUntil(0)(num))
      new TurtleSet(turtles)

    # (Number) => Agent
    getTurtle: (id) ->
      @_turtlesById[id] ? Nobody

    # (String, Number) => Agent
    getTurtleOfBreed: (breedName, id) ->
      turtle = @getTurtle(id)
      if turtle.getBreedName().toUpperCase() is breedName.toUpperCase()
        turtle
      else
        Nobody

    # (Object[Any], Number) => Unit
    importState: (turtleState, nextIndex) ->
      turtleState.forEach(
        ({ who, color, heading, xcor, ycor, shape, labelColor, breed, isHidden, size, penSize, penMode }) =>
          newTurtle = @_createTurtle(who, color, heading, xcor, ycor, breed, "", labelColor, isHidden, size, shape)
          newTurtle.penManager.setPenMode(penMode)
          newTurtle.penManager.setSize(penSize)
      )
      @_idManager.importState(nextIndex)
      return

    # () => Array[Object]
    #TODO: Add object hashmap that holds breeds-own variable names for that
    #sweet O(1) access and to avoid repetition.
    exportState: ->
      allVars = []
      filterTurtles = (turtle) =>
        tempExport = {
          'who': turtle['id'],
          'color': turtle.getVariable('color'),
          'heading': turtle.getVariable('heading'),
          'xcor': turtle.getVariable('xcor'),
          'ycor': turtle.getVariable('ycor'),
          'shape': turtle.getVariable('shape'),
          'label': turtle.getVariable('label'),
          'labelColor': turtle.getVariable('label-color'),
          'breed': turtle.getVariable('breed'),
          'isHidden': turtle.getVariable('hidden?'),
          'size': turtle.getVariable('size'),
          'penSize': turtle.penManager.getSize(),
          'penMode': turtle.penManager.getMode(),
        }
        allVars = unique(concat(allVars)(turtle['varNames']().slice(13)))
        pipeline(map((turtlesOwn) -> tempExport[turtlesOwn] = turtle.getVariable(turtlesOwn)))(allVars)
        tempExport
      pipeline(map(filterTurtles))(@turtles().toArray())

    # () => TurtleSet
    turtles: ->
      new TurtleSet(@_turtles, "turtles")

    # (String) => TurtleSet
    turtlesOfBreed: (breedName) =>
      breed = @_breedManager.get(breedName)
      new TurtleSet(breed.members, breedName)

    # () => Unit
    _clearTurtlesSuspended: ->
      @_idManager.suspendDuring(() => @clearTurtles())
      return

    # (Number, Number, Number, Number, Breed, String, Number, Boolean, Number, String, (Updatable) => PenManager) => Turtle
    _createNewTurtle: (color, heading, xcor, ycor, breed, label, lcolor, isHidden, size, shape, genPenManager) =>
      @_createTurtle(@_idManager.next(), color, heading, xcor, ycor, breed, label, lcolor, isHidden, size, shape, genPenManager)

    # (Number, Number, Number, Number, Number, Breed, String, Number, Boolean, Number, String, (Updatable) => PenManager) => Turtle
    _createTurtle: (id, color, heading, xcor, ycor, breed, label, lcolor, isHidden, size, shape, genPenManager) ->
      turtle = new Turtle(@_world, id, @_updater.updated, @_updater.registerPenTrail, @_updater.registerTurtleStamp, @_updater.registerDeadTurtle, @_createNewTurtle, @_removeTurtle, color, heading, xcor, ycor, breed, label, lcolor, isHidden, size, shape, genPenManager)
      @_updater.updated(turtle)(Builtins.turtleBuiltins...)
      @_turtles.push(turtle)
      @_turtlesById[id] = turtle
      turtle

    # (Number) => Unit
    _removeTurtle: (id) =>
      turtle = @_turtlesById[id]
      @_turtles.splice(@_turtles.indexOf(turtle), 1)
      delete @_turtlesById[id]
      return
