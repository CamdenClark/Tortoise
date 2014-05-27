#@# Attach it to an `Observer` object
define(['integration/lodash'], (_) ->
  class Globals
    vars: []
    # Tells runtime how many globals to reserve space for and initialize to `0` --JAB (4/29/14)
    init: (n) ->
      @vars = _(0).range(n).map(-> 0).value()
      return
    clear: (n) -> #@# Weird that this function takes arguments...
      _(n).range(@vars.length).forEach((num) => @vars[num] = 0; return)
      return
    getGlobal: (n) ->
      @vars[n]
    setGlobal: (n, value) ->
      @vars[n] = value
      return
)