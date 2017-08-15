{ version }     = require('meta')

{ map, isEmpty, flatMap, filter, foldl, concat, zip, toObject, unique }     = require('brazierjs/array')
{ pipeline, flip }                                                  = require('brazierjs/function')
{ keys, values }                                                    = require('brazierjs/object')
{ isString }                                                        = require('brazierjs/type')

# Polyfill for padStart prototype (ES2017 addition)... --CC 8/14/17
if !String.prototype.padStart
  String.prototype.padStart = (max, fillString) ->
    padStart(this, max, fillString)

  padStart = (text, max, mask) ->
    cur = text.length
    if max <= cur
      return text
    masked = max - cur
    filler = String(mask) || ' '
    while (filler.length < masked)
        filler += filler
    fillerSlice = filler.slice(0, masked)
    fillerSlice + text
#End polyfill..

globalDefaultVars = {
  'minPxcor': 'min-pxcor', 'minPycor': 'min-pycor', 'maxPxcor': 'max-pxcor',
  'maxPycor': 'max-pycor', 'perspective': 'perspective', 'subject': 'subject', 'directedLinks': 'directed-links',
  'ticks': 'ticks'
}

turtleDefaultVarArr = ['who', 'color', 'heading', 'xcor', 'ycor', 'shape', 'label', 'label-color',
  'breed', 'hidden?', 'size', 'pen-size', 'pen-mode']
linkDefaultVarArr = ['end1', 'end2', 'color', 'label', 'label-color', 'hidden?',
  'breed', 'thickness', 'shape', 'tie-mode']


#Begin utility functions.
#These don't look at the world state. -- CC 8/14/17

# () => String
formatDate = () ->
  date = new Date()
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

# (String) -> String
quoteWrap = (str) ->
  '"' + str + '"'

# (String) => String
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

# ((Object) => String) => String
replaceCamelCase = (varMap) -> (label) ->
  if varMap.hasOwnProperty(label) then varMap[label] else label

# (Array[Array[Any]]) => Array[Array[Any]]
transpose = (arrays) ->
  arrays[0].map((_, i) -> arrays.map((array) -> array[i]))

# exportAgents is a utility function because the method for transferring
# from state to desirable objects for turtles, links, and plots
# are highly similar. Therefore, we created one function that takes
# an agent-set, a function to determine whether a breed is of a certain
# agent-type, a default variable array, and the agent type. It spits out
# an array of objects that are fed to the exportWorld function (which the
# output of which turns into a CSV on the browser side). --CC 8/14/2017

# (Array[Object], (String -> Boolean), Array[String], String) => Array[Object]
exportAgents = (agents, isThisAgentType, varArr, typeName) ->
  varList = pipeline(filter(isThisAgentType), flatMap((x) -> x.varNames), unique, concat(varArr))(values(@breedManager.breeds()))
  if typeName == 'patches'
    varList = agents[0].varNames()
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

#End utility functions.

#The following functions all look at the world state.

# () => String
directedLinksDefault = () ->
  if isEmpty(@links().toArray())
    'NEITHER'
  else if @breedManager.links()._isDirectedLinkBreed
    'DIRECTED'
  else
    'UNDIRECTED'

# () => Object
exportGlobals = () ->
  tempExport = {
    minPxcor: @topology.minPxcor,
    maxPxcor: @topology.maxPxcor,
    minPycor: @topology.minPycor,
    maxPycor: @topology.maxPycor,
    perspective: @observer.getPerspectiveNum(),
    subject: @observer.subject(),
    nextIndex: @turtleManager.nextIndex(),
    directedLinks: directedLinksDefault.call(this),
    ticks: if @ticker.ticksAreStarted() then @ticker.tickCount() else -1
  }
  if @observer.varNames().length == 0
    tempExport
  pipeline(map((extraGlobal) => tempExport[extraGlobal] = @observer.getGlobal(extraGlobal)))(@observer.varNames().sort())
  tempExport

# () => Object[Array[Object]]
exportState = () ->
  turtleDefaultVarArr = ['who', 'color', 'heading', 'xcor', 'ycor', 'shape', 'label', 'label-color',
    'breed', 'hidden?', 'size', 'pen-size', 'pen-mode']
  linkDefaultVarArr = ['end1', 'end2', 'color', 'label', 'label-color', 'hidden?',
    'breed', 'thickness', 'shape', 'tie-mode']
  {
    'patches': exportAgents.call(this, @patches().toArray(), (-> false), ['pxcor', 'pycor', 'pcolor', 'plabel', 'plabel-color'], 'patches'),
    'turtles': exportAgents.call(this, @turtleManager.turtles().toArray(), ((breed) -> not breed.isLinky()), turtleDefaultVarArr, 'turtles'),
    'links': exportAgents.call(this, @linkManager.links().toArray(), ((breed) -> breed.isLinky()), linkDefaultVarArr, 'links'),
    'globals': exportGlobals.call(this),
    'randomState': @rng.exportState(),
    'plots': @_plotManager.exportState()
  }

# (Object) => Array[String]
csvPlot = (plot) ->
  plotDefaultVars = {
    'xMin': 'x min', 'xMax': 'x max', 'yMin': 'y min', 'yMax': 'y max', 'isAutoplotting': 'autoplot?',
    'currentPen': 'current pen', 'isLegendOpen': 'legend open?', 'numPens': 'number of pens'
  }
  penDefaultVars = {
    'name': 'pen name', 'isPenDown': 'pen down?', 'mode': 'mode', 'interval': 'interval',
    'color': 'color', 'x': 'x'
  }
  pointDefaultVars = { 'x': 'x', 'y': 'y', 'color': 'color', 'penMode': 'pen down?' }
  transposedPens = pipeline(transpose, map((row) -> map(map(quoteWrapVals))(row)), map((row) -> row.join(',')))(map((pen) -> map((point) -> [point['x'], point['y'], point['color'], point['penMode']])(pen['points']))(plot['pens'])).join('\n')
  [
    quoteWrapVals(plot['name']),
    pipeline(map(replaceCamelCase(plotDefaultVars)), map(quoteWrap))(keys(plot['vars'])).join(','),
    pipeline(values, map(quoteWrapVals))(plot['vars']).join(','),
    '',
    pipeline(values, map(quoteWrap))(penDefaultVars),
    map((pen) -> pipeline(map(quoteWrapVals))(values(pen['vars'])).join(','))(plot['pens']).join('\n'),
    '',
    map((pen) -> quoteWrapVals(pen['vars']['name']))(plot['pens']).join(',,,,'),
    flatMap((pen) -> map(quoteWrap)(values(pointDefaultVars)))(plot['pens']).join(','),
    if isEmpty(transposedPens) then '' else transposedPens + '\n'
  ]

# (String) => String
exportPlot = (plotName) ->
  defaultExportPlot = [
    '"export-world data (NetLogo Web ' + version + ')"',
    '"[IMPLEMENT .NLOGO]"',
    quoteWrap(formatDate()),
    '',
    quoteWrap('GLOBALS'),
    pipeline(map(replaceCamelCase(globalDefaultVars)), map(quoteWrap))(keys(exportGlobals.call(this)).slice(8)).join(','),
    pipeline(map(quoteWrapVals))(values(exportGlobals.call(this)).slice(8)).join(','),
    ''
  ]
  plots = @_plotManager.exportState()
  desiredPlot = filter((x) -> x.name == plotName)(plots['plots'])
  if isEmpty(desiredPlot)
    ''
  else
    concat(defaultExportPlot)(csvPlot(desiredPlot[0])).join('\n')

# () => String
exportAllPlots = () ->
  defaultExportPlot = [
    '"export-world data (NetLogo Web ' + version + ')"',
    '"[IMPLEMENT .NLOGO]"',
    quoteWrap(formatDate()),
    '',
    quoteWrap('GLOBALS'),
    pipeline(map(replaceCamelCase(globalDefaultVars)), map(quoteWrap))(keys(exportGlobals.call(this)).slice(8)).join(','),
    pipeline(map(quoteWrapVals))(values(exportGlobals.call(this)).slice(8)).join(','),
    ''
  ]
  plots = @_plotManager.exportState()
  foldl((acc, x) -> concat(acc)(csvPlot(x)))(defaultExportPlot)(plots['plots']).join('\n')

# () => String
exportWorld = () ->
  exportedState = exportState.call(this)

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
  plotCSV = concat(flatMap(csvPlot)(exportedState['plots']['plots']))(['"EXTENSIONS"'])
  exportCSV = concat([
    '"export-world data (NetLogo Web ' + version + ')"',
    '"[IMPLEMENT .NLOGO]"',
    quoteWrap(formatDate()),
    '',
    quoteWrap('RANDOM STATE'),
    quoteWrap(exportedState['randomState']),
    '',
    quoteWrap('GLOBALS'),
    pipeline(map(replaceCamelCase(globalDefaultVars)), map(quoteWrap))(keys(exportedState['globals'])).join(','),
    pipeline(map(quoteWrapVals))(values(exportedState['globals'])).join(','),
    '',
    quoteWrap('TURTLES'),
    concat(map(quoteWrap)(values(turtleDefaultVars)))(pipeline(filter((breed) -> not breed.isLinky()), flatMap((x) -> x.varNames), unique, map(quoteWrap))(values(@breedManager.breeds()))).join(','),
    if isEmpty(exportedState['turtles']) then '' else map((turt) -> pipeline(map(quoteWrapVals))(values(turt)).join(','))(exportedState['turtles']).join('\n') + '\n',
    quoteWrap('PATCHES'),
    pipeline(map(replaceCamelCase(patchDefaultVars)), map(quoteWrap))(keys(exportedState['patches'][0])).join(','),
    map((patch) -> pipeline(map(quoteWrapVals))(values(patch)).join(','))(exportedState['patches']).join('\n'),
    '',
    quoteWrap('LINKS'),
    concat(map(quoteWrap)(values(linkDefaultVars)))(pipeline(filter((breed) -> breed.isLinky()), flatMap((x) -> x.varNames), unique, map(quoteWrap))(values(@breedManager.breeds()))).join(','),
    if isEmpty(exportedState['links']) then '' else map((link) -> pipeline(map(quoteWrapVals))(values(link)).join(','))(exportedState['links']).join('\n') + '\n',
    '',
    quoteWrap('OUTPUT'),
    quoteWrap('PLOTS'),
    if exportedState['plots']['currentPlot']? then quoteWrap(exportedState['plots']['currentPlot'].name) else quoteWrap(''),
  ])(plotCSV)
  exportCSV.join('\n')


module.exports = { exportPlot, exportAllPlots, exportWorld }
