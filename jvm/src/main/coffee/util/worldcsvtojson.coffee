{ foldl, tail, zip } = require('brazierjs/array')
{ pipeline         } = require('brazierjs/function')

parse = require('csv-parse/lib/sync')

# type ImpObj    = Object[Any]
# type ImpArr    = Array[ImpObj]
# type Converter = (String) => Any
# type Row       = Array[String]
# type Parser[T] = (Array[Row], Schema) => T
# type Schema    = Object[Converter]

class WorldState
  #            (ImpObj         , Object[String], String   , ImpArr  , ImpArr  , ImpArr, String , ImpArr, ImpObj     )
  constructor: (@builtInGlobals, @userGlobals  , @rngState, @turtles, @patches, @links, @output, @plots, @extensions) ->

# (String) => String
csvNameToSaneName = (csvName) ->

  if csvName isnt "nextIndex"

    replaceAll = (str, regex, f) ->
      match = str.match(regex)
      if match?
        { 0: fullMatch, 1: group, index } = match
        prefix  = str.slice(0, index)
        postfix = str.slice(index + fullMatch.length)
        replaceAll("#{prefix}#{f(group)}#{postfix}", regex, f)
      else
        str

    lowered    = csvName.toLowerCase()
    camelCased = replaceAll(lowered, /[ \-]+([a-z0-9])/, (str) -> str.toUpperCase())

    qMatch = camelCased.match(/^(\w)(.*)\?$/, )
    if qMatch?
      { 1: firstLetter, 2: remainder } = qMatch
      "is#{firstLetter.toUpperCase()}#{remainder}"
    else
      camelCased

  else

    csvName



# START SCHEMA STUFF

# (String) => Boolean
parseBool = (x) ->
  x.toLowerCase() is "true"

# Only used to mark things that we should delay converting until later --JAB (4/6/17)
# [T] @ (T) => T
identity = (x) ->
  x

# (String) => String
parseString = (str) ->
  match = str.match(/^"(.*)"$/)
  if match?
    match[1]
  else
    throw new Error("Failed to match on #{str}")

# Object[Schema]
nameToSchema = {
  plots: {
    color:        parseFloat
  , currentPen:   parseString
  , interval:     parseFloat
  , isAutoplot:   parseBool
  , isLegendOpen: parseBool
  , isPenDown:    parseBool
  , mode:         parseInt
  , penName:      parseString
  , xMax:         parseFloat
  , xMin:         parseFloat
  , x:            parseFloat
  , yMax:         parseFloat
  , yMin:         parseFloat
  , y:            parseFloat
  }
  randomState: {
    value: identity
  }
  globals: {
    directedLinks: parseString
  , minPxcor:      parseInt
  , maxPxcor:      parseInt
  , minPycor:      parseInt
  , maxPycor:      parseInt
  , nextIndex:     parseInt
  , perspective:   parseInt
  , subject:       identity
  , ticks:         parseFloat
  }
  turtles: {
    breed:      identity
  , color:      parseFloat
  , heading:    parseFloat
  , isHidden:   parseBool
  , labelColor: parseFloat
  , label:      identity
  , penMode:    parseString
  , penSize:    parseFloat
  , shape:      parseString
  , size:       parseFloat
  , who:        parseInt
  , xcor:       parseFloat
  , ycor:       parseFloat
  }
  patches: {
    pcolor:      parseFloat
  , plabelColor: parseFloat
  , plabel:      identity
  , pxcor:       parseInt
  , pycor:       parseInt
  }
  links: {
    breed:      identity
  , color:      parseFloat
  , end1:       identity
  , end2:       identity
  , isHidden:   parseBool
  , labelColor: parseFloat
  , label:      identity
  , shape:      parseString
  , thickness:  parseFloat
  , tieMode:    parseString
  }
  output: {
    value: parseString
  }
  extensions: {}
}

# END SCHEMA STUFF



# START PARSER STUFF

# Parser[String]
singletonParse = ([[item]], schema) ->
  schema.value(item)

# Parser[ImpArr]
arrayParse = ([keys, rows...], schema) ->

  f =
    (acc, row) ->
      obj = { extraVars: {} }
      for rawKey, index in keys
        saneKey = csvNameToSaneName(rawKey)
        value   = row[index]
        if schema[saneKey]?
          obj[saneKey] = schema[saneKey](value)
        else if value isnt ""
          obj.extraVars[rawKey] = value # DO NOT USE `saneKey`!  Do not touch user global names! --JAB (8/2/17)
      acc.concat([obj])

  foldl(f)([])(rows)

# Parser[ImpObj]
globalParse = (csvBucket, schema) ->
  arrayParse(csvBucket, schema)[0]

# Parser[ImpObj]
plotParse = (csvBucket, schema) ->

  parseEntity = (acc, rowIndex, upperBound, valueRowOffset, valueColumnOffset) ->
    for columnIndex in [0...upperBound]
      columnName        = csvNameToSaneName(csvBucket[rowIndex                 ][columnIndex])
      value             =                   csvBucket[rowIndex + valueRowOffset][columnIndex + valueColumnOffset]
      acc[columnName] = (schema[columnName] ? parseInt)(value)
    acc

  output = { default: csvBucket[0]?[0] ? null, plots: [] }

  # Iterate over every plot
  csvIndex = 1

  while csvIndex < csvBucket.length

    plot     = parseEntity({ name: parseString(csvBucket[csvIndex++][0]) }, csvIndex, csvBucket[csvIndex].length, 1, 0)
    penCount = plot.numberOfPens
    delete plot.penCount
    csvIndex += 2

    plot.pens = [0...penCount].map((i) -> parseEntity({ points: [] }, csvIndex, csvBucket[csvIndex].length, 1 + i, 0))
    csvIndex += 2 + penCount

    # For each pen, parsing of the list of points associated with the pen
    pointsIndex = 1
    while csvIndex + pointsIndex < csvBucket.length and csvBucket[csvIndex + pointsIndex].length isnt 1
      length = csvBucket[csvIndex].length / penCount
      for penIndex in [0...penCount]
        point  = parseEntity({}, csvIndex, length, pointsIndex, penIndex * length)
        plot.pens[penIndex].points.push(point)
      pointsIndex++
    csvIndex += pointsIndex

    output.plots.push(plot)

  output

# Parser[ImpObj]
extensionParse = (csvBucket, schema) ->
  output = {}
  for [item] in csvBucket
    if not item.startsWith('{{')
      output[item] = []
    else
      extNames  = Object.keys(output)
      latestExt = output[extNames[extNames.length - 1]]
      latestExt.push(item)
  output

# Object[Parser[Any]]
buckets = {
  extensions:  extensionParse
, globals:     globalParse
, links:       arrayParse
, output:      singletonParse
, patches:     arrayParse
, plots:       plotParse
, randomState: singletonParse
, turtles:     arrayParse
}

# END PARSER STUFF



# (ImpObj, Array[String]) => (ImpObj, Object[String])
extractGlobals = (globals, knownNames) ->
  builtIn = {}
  user    = {}
  for key, value of globals
    if key in knownNames
      builtIn[key] = value
    else
      user[key] = value
  [builtIn, user]

# (String) => WorldState
module.exports =
  (csvText) ->

    parsedCSV = parse(csvText, {
      comment: '#'
      skip_empty_lines: true
      relax_column_count: true
    })

    clusterRows =
      ([acc, latestRows], row) ->

        saneName =
          try
            if row.length is 1
              csvNameToSaneName(row[0])
            else
              undefined
          catch ex
            undefined

        if saneName? and saneName of buckets
          rows = []
          acc[saneName] = rows
          [acc, rows]
        else if latestRows?
          latestRows.push(row)
          [acc, latestRows]
        else
          [acc, latestRows]

    [bucketToRows, _] = foldl(clusterRows)([{}, undefined])(parsedCSV)

    world = {}

    for name, bucketParser of buckets when bucketToRows[name]?
      world[name] = bucketParser(bucketToRows[name], nameToSchema[name])

    { globals, randomState, turtles, patches, links, output, plots, extensions } = world

    userGlobals = globals.extraVars
    delete globals.extraVars
    builtInGlobals = globals

    new WorldState(builtInGlobals, userGlobals, randomState, turtles, patches, links, output, plots, extensions)
