{ version }     = require('meta')

{ map, isEmpty, flatMap, filter, foldl, concat, zip, toObject }     = require('brazierjs/array')
{ pipeline, flip }                                                  = require('brazierjs/function')
{ keys, values }                                                    = require('brazierjs/object')
{ isString }                                                        = require('brazierjs/type')

exportAgents = (agents, isThisAgentType, varArr, typeName) ->
  varList = pipeline(filter(isThisAgentType), flatMap((x) -> x.varNames), flip(concat)(varArr))(values(@breedManager.breeds()))
  varList = pipeline(filter(isThisAgentType), flatMap((x) -> x.varNames), concat(varArr))(values(@breedManager.breeds()))
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

replaceCamelCase = (varMap) -> (label) ->
  if varMap.hasOwnProperty(label) then varMap[label] else label

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

directedLinksDefault = () ->
  if isEmpty(@links().toArray())
    'NEITHER'
  else if @breedManager.links()._isDirectedLinkBreed
    'DIRECTED'
  else
    'UNDIRECTED'

transpose = (arrays) ->
  arrays[0].map((_, i) -> arrays.map((array) -> array[i]))

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
    ticks: @ticker.tickCount()
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
    pipeline(transpose, map((row) -> map(map(quoteWrapVals))(row)), map((row) -> row.join(',')))(map((pen) -> map((point) -> [point['x'], point['y'], point['color'], point['penMode']])(pen['points']))(plot['pens'])).join('\n'),
    ''
  ]

module.exports =
    () ->
      exportedState = exportState.call(this)
      timeStampString = formatDate()

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
      plotCSV = concat(flatMap(csvPlot)(exportedState['plots']['plots']))(['"EXTENSIONS"'])
      exportCSV = concat([
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
        concat(map(quoteWrap)(values(turtleDefaultVars)))(pipeline(filter((breed) -> not breed.isLinky()), flatMap((x) -> x.varNames), map(quoteWrap))(values(@breedManager.breeds()))).join(','),
        map((turt) -> pipeline(map(quoteWrapVals))(values(turt)).join(','))(exportedState['turtles']).join('\n'),
        '',
        quoteWrap('PATCHES'),
        pipeline(map(replaceCamelCase(patchDefaultVars)), map(quoteWrap))(keys(exportedState['patches'][0])).join(','),
        map((patch) -> pipeline(map(quoteWrapVals))(values(patch)).join(','))(exportedState['patches']).join('\n'),
        '',
        quoteWrap('LINKS'),
        concat(map(quoteWrap)(values(linkDefaultVars)))(pipeline(filter((breed) -> breed.isLinky()), flatMap((x) -> x.varNames), map(quoteWrap))(values(@breedManager.breeds()))).join(','),
        if isEmpty(exportedState['links']) then '' else map((link) -> pipeline(map(quoteWrapVals))(values(link)).join(','))(exportedState['links']).join('\n') + '\n',
        '',
        quoteWrap('PLOTS'),
        if exportedState['plots']['currentPlot']? then quoteWrap(exportedState['plots']['currentPlot'].name) else quoteWrap(''),
      ])(plotCSV)
      exportCSV.join('\n')
