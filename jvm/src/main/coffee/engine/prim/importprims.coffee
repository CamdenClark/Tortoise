module.exports.Config =
  class ImportConfig
    # (Unit -> File) -> ImportConfig
    constructor: (@importWorld = (->)) ->

module.exports.Prims =
  class ImportPrims
    # ImportConfig, (File -> Unit) -> ImportPrims
    constructor: ({ importWorld }, importWorldCB) ->
      @importWorld = (filename) -> importWorldCB(importWorld())
