# (C) Uri Wilensky. https://github.com/NetLogo/Tortoise

module.exports.Config =
  class ExportConfig
    # {(String -> Unit), (String -> String -> Unit)} -> ExportConfig
    constructor: (@exportOutput = (->), @exportCSV = (-> ->)) ->

module.exports.Prims =
  class ExportPrims
    # ExportConfig, (Unit -> String), (Unit -> String), (String -> String) -> ExportPrims
    constructor: ({ @exportOutput, exportCSV }, expWorldCB, expAllPlotsCB, expPlotCB) ->
        @exportWorld    = (filename)       -> exportCSV(expWorldCB())(filename)
        @exportAllPlots = (filename)       -> exportCSV(expAllPlotsCB())(filename)
        @exportPlot     = (plot, filename) -> exportCSV(expPlotCB(plot))(filename)
