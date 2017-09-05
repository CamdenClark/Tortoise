{ version }     = require('meta')

{ concat, filter, flatMap, foldl, isEmpty, map, toObject, unique, zip }  = require('brazierjs/array')
{ flip, id, pipeline, tee }                                              = require('brazierjs/function')
{ keys, values }                                                         = require('brazierjs/object')
{ isString }                                                             = require('brazierjs/type')

globalDefaultVars   = {
  'minPxcor': 'min-pxcor', 'minPycor': 'min-pycor', 'maxPxcor': 'max-pxcor',
  'maxPycor': 'max-pycor', 'perspective': 'perspective', 'subject': 'subject', 'directedLinks': 'directed-links',
  'ticks': 'ticks'
}

linkDefaultVarArr   = [
  'end1', 'end2', 'color', 'label', 'label-color', 'hidden?',
  'breed', 'thickness', 'shape', 'tie-mode'
]

turtleDefaultVarArr = [
  'who', 'color', 'heading', 'xcor', 'ycor', 'shape', 'label', 'label-color',
  'breed', 'hidden?', 'size', 'pen-size', 'pen-mode'
]

# Polyfill for padStart prototype (ES2017 addition)... --CC 8/14/17
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

#Begin utility functions.
#These don't look at the world state. -- CC 8/14/17

# Thanks to user "le_m" for graciously providing a much better
# solution to this problem. https://codereview.stackexchange.com/a/164141/139601

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
  res = dateFormat.map((value, i) => padStart(value.toString(), digits[i], '0') + seperators[i])
  res.join('')

# (Array[String]) -> String
joinCommaed  = (x) -> x.join(',')

# (Array[String]) -> String
joinNewlined = (x) -> x.join('\n')

# (String) -> String
quoteWrap = (str) ->
  '"' + str + '"'

# (String) => String
quoteWrapVals = (str) ->
  if isString(str)
    if str[0] == '{' and str.length > 0
      '"' + str + '"'
    else
      '"""' + str + '"""'
  else if str.toString()[0] == '('
    str.toString().replace('(', '{').replace(')', '}')
  else if str?
    '"' + str + '"'
  else
    str

# ((Object) => String) => String
replaceCamelCase = (varMap) -> (label) ->
  varMap[label] ? label

# (Array[Array[Any]]) => Array[Array[Any]]
transpose = (arrays) ->
  arrays[0].map((_, i) -> arrays.map((array) -> array[i]))

# csvPlot takes a plot object from plotManager.exportState() and
# returns an array of strings that will be join('\n')ed when creating
# the CSV

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

  # Whoa, what's going on here? NetLogo demands we have the points in a specific
  # format, which happens to be the transpose of the matrix of points as stored
  # in the world state. *shrugs* --CC 8/14/17

  transposedPens = pipeline(transpose, map((row) -> map(map(quoteWrapVals))(row)), map((row) -> row.join(',')))(map((pen) -> map((point) -> [point['x'], point['y'], point['color'], point['penMode']])(pen['points']))(plot['pens'])).join('\n')
  [
    quoteWrapVals(plot['name']),
    pipeline(keys, map(replaceCamelCase(plotDefaultVars)), map(quoteWrap), joinCommaed)(plot['vars']),
    pipeline(values, map(quoteWrapVals), joinCommaed)(plot['vars']),
    '',
    pipeline(values, map(quoteWrap))(penDefaultVars),
    map((pen) -> pipeline(values, map(quoteWrapVals), joinCommaed)(pen['vars']))(plot['pens']).join('\n'),
    '',
    map((pen) -> quoteWrapVals(pen['vars']['name']))(plot['pens']).join(',,,,'),
    flatMap((pen) -> map(quoteWrap)(values(pointDefaultVars)))(plot['pens']).join(','),
    if isEmpty(transposedPens) then '' else transposedPens + '\n'
  ]

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
  else if @breedManager.isDirected()
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
  pipeline(map((extraGlobal) => tempExport[extraGlobal] = @observer.getGlobal(extraGlobal)))(@observer.varNames().sort())
  tempExport

# () => Object[Array[Object]]
exportState = () ->
  {
    'patches': exportAgents.call(this, @patches().toArray(), (-> false), ['pxcor', 'pycor', 'pcolor', 'plabel', 'plabel-color'], 'patches'),
    'turtles': exportAgents.call(this, @turtleManager.turtles().toArray(), ((breed) -> not breed.isLinky()), turtleDefaultVarArr, 'turtles'),
    'links': exportAgents.call(this, @linkManager.links().toArray(), ((breed) -> breed.isLinky()), linkDefaultVarArr, 'links'),
    'globals': exportGlobals.call(this),
    'randomState': @rng.exportState(),
    'plots': @_plotManager.exportState()
  }

# (String) => String
exportPlot = (plotName) ->
  defaultExportPlot = [
    '"export-world data (NetLogo Web ' + version + ')"',
    '"[IMPLEMENT .NLOGO]"',
    quoteWrap(formatDate()),
    '',
    quoteWrap('GLOBALS'),
    pipeline(map(replaceCamelCase(globalDefaultVars)), map(quoteWrap))(keys(exportGlobals.call(this)).slice(8)).join(','),
    map(quoteWrapVals)(values(exportGlobals.call(this)).slice(8)).join(','),
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
  globals = exportGlobals.call(this)
  defaultExportPlot = [
    '"export-world data (NetLogo Web ' + version + ')"',
    '"[IMPLEMENT .NLOGO]"',
    quoteWrap(formatDate()),
    '',
    quoteWrap('GLOBALS'),
    pipeline(keys, ((x) -> x.slice(8)), map(replaceCamelCase(globalDefaultVars)), map(quoteWrap), joinCommaed)(globals),
    pipeline(values, ((x) -> x.slice(8)), map(quoteWrapVals), joinCommaed)(globals),
    ''
  ]
  plots = @_plotManager.exportState()
  foldl((acc, x) -> concat(acc)(csvPlot(x)))(defaultExportPlot)(plots['plots']).join('\n')

# () => String
exportWorld = () ->
  { patches, turtles, links, globals, randomState, plots } = exportState.call(this)

  plotCSV = concat(flatMap(csvPlot)(plots['plots']))(['"EXTENSIONS"'])

  globalVarString   = pipeline(keys, map(replaceCamelCase(globalDefaultVars)), map(quoteWrap), joinCommaed)(globals)
  globalValString   = pipeline(values, map(quoteWrapVals), joinCommaed)(globals)

  turtleDefaultVars = map(quoteWrap)(turtleDefaultVarArr)
  turtleVarString   = pipeline(values, filter((breed) -> not breed.isLinky()), flatMap((x) -> x.varNames), unique, map(quoteWrap), concat(turtleDefaultVars), joinCommaed)(@breedManager.breeds())
  turtleValString   = if isEmpty(turtles) then '' else map((turt) -> pipeline(values, map(quoteWrapVals), joinCommaed)(turt))(turtles).join('\n') + '\n'

  patchVarString    = pipeline(keys, map(quoteWrap), joinCommaed)(patches[0])
  patchValString    = map((patch) -> pipeline(values, map(quoteWrapVals), joinCommaed)(patch))(patches).join('\n')

  linkDefaultVars   = map(quoteWrap)(linkDefaultVarArr)
  linkVarString     = pipeline(values, filter((breed) -> breed.isLinky()), flatMap((x) -> x.varNames), unique, map(quoteWrap), concat(linkDefaultVars), joinCommaed)(@breedManager.breeds())
  linkValString     = if isEmpty(links) then '' else map((link) -> pipeline(values, map(quoteWrapVals), joinCommaed)(link))(links).join('\n') + '\n'

  currentPlot       = if plots['currentPlot']? then quoteWrap(plots['currentPlot'].name) else quoteWrap('')

  exportCSV = concat([
    '"export-world data (NetLogo Web ' + version + ')"',
    '"[IMPLEMENT .NLOGO]"',
    quoteWrap(formatDate()),
    '',
    quoteWrap('RANDOM STATE'),
    quoteWrap(randomState),
    '',
    quoteWrap('GLOBALS'),
    globalVarString,
    globalValString,
    '',
    quoteWrap('TURTLES'),
    turtleVarString,
    turtleValString,
    quoteWrap('PATCHES'),
    patchVarString,
    patchValString,
    '',
    quoteWrap('LINKS'),
    linkVarString,
    linkValString,
    '',
    quoteWrap('PLOTS'),
    currentPlot
  ])(plotCSV)
  exportCSV.join('\n')


module.exports = { exportPlot, exportAllPlots, exportWorld }
