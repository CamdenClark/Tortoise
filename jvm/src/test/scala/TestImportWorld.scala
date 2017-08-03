// (C) Uri Wilensky. https://github.com/NetLogo/Tortoise

package org.nlogo.tortoise

import jsengine.Nashorn
import org.scalatest.FunSuite
import org.nlogo.core.Resource

import java.nio.file.Paths

// just basic smoke tests that basic Tortoise engine functionality is there,
// without involving the Tortoise compiler

class TestImportWorld extends FunSuite {

  //random-seed = 0 on both NLD and NLW

  private def csvPath(name: String): String =
    s"${Paths.get("").toAbsolutePath}/resources/test/export-world/exportWorldTest$name.csv"

  val modelsToTest = Array(("AIDS", "procedures.setup()"), ("Network Example", "procedures.setup(); procedures.go(); procedures.go();"),
    ("Climate Change", "procedures.setup(); procedures.addCloud(); procedures.addCo2();"))

  for ( modelTuple <- modelsToTest ) {
    var exportWorldToImport = scala.util.Try(Resource.asString("/export-world/exportWorldTest" + modelTuple._1 + ".csv"))
              .getOrElse("Could not find NLD " + modelTuple._1 + ".csv file").trim

    var modelDump = scala.util.Try(Resource.asString("/dumps/" + modelTuple._1 + ".js"))
              .getOrElse("Could not find " + modelTuple._1 + " js model dumps").trim

    var nashorn = new Nashorn
    nashorn.eval("""if (!String.prototype.padStart) {
          String.prototype.padStart = function (max, fillString) {
            return padStart(this, max, fillString);
          };
        }

        function padStart (text, max, mask) {
          const cur = text.length;
          if (max <= cur) {
            return text;
          }
          const masked = max - cur;
          let filler = String(mask) || ' ';
          while (filler.length < masked) {
            filler += filler;
          }
          const fillerSlice = filler.slice(0, masked);
          return fillerSlice + text;
        }""")
    nashorn.eval("""var workspace   = tortoise_require('engine/workspace')""")
    nashorn.eval(modelDump)
    nashorn.eval(s"""workspace.importWorldString('${exportWorldToImport}')""")
    var exportResultNLD = nashorn.eval("""world.exportWorld()""").asInstanceOf[String]

    nashorn = new Nashorn
    nashorn.eval("""if (!String.prototype.padStart) {
          String.prototype.padStart = function (max, fillString) {
            return padStart(this, max, fillString);
          };
        }

        function padStart (text, max, mask) {
          const cur = text.length;
          if (max <= cur) {
            return text;
          }
          const masked = max - cur;
          let filler = String(mask) || ' ';
          while (filler.length < masked) {
            filler += filler;
          }
          const fillerSlice = filler.slice(0, masked);
          return fillerSlice + text;
        }""")
    nashorn.eval("""var workspace   = tortoise_require('engine/workspace')""")
    nashorn.eval(modelDump)
    nashorn.eval("workspace.rng.setSeed(0)")
    nashorn.eval(modelTuple._2)

    var exportResultNLW = nashorn.eval("""world.exportWorld()""").asInstanceOf[String]

    var splitExportResultNLW = exportResultNLW.split("\n\n").toArray

    var splitExportResultNLD = exportResultNLD.split("\n\n").toArray

    test(modelTuple._1 + ": Random state exported the same way?") {
      assertResult(splitExportResultNLD(1))(splitExportResultNLW(1))
    }

    test(modelTuple._1 + ": Global variables exported correctly?") {
      assertResult(splitExportResultNLD(2).split("\n")(1))(splitExportResultNLW(2).split("\n")(1))
    }

    test(modelTuple._1 + ": All global values exported correctly?") {
      assertResult(splitExportResultNLD(2).split("\n").slice(2, splitExportResultNLD(2).split("\n").length))(
        splitExportResultNLW(2).split("\n").slice(2, splitExportResultNLW(2).split("\n").length))
    }

    test(modelTuple._1 + ": Turtle variables exported correctly?") {
      assertResult(splitExportResultNLD(3).split("\n"))(splitExportResultNLW(3).split("\n"))
    }

    test(modelTuple._1 + ": All turtle values exported correctly?") {
      assertResult(splitExportResultNLD(3).split("\n").slice(2, splitExportResultNLD(3).split("\n").length))(
        splitExportResultNLW(3).split("\n").slice(2, splitExportResultNLW(3).split("\n").length))
    }

    test(modelTuple._1 + ": Patch variables exported correctly?") {
      assertResult(splitExportResultNLD(4).split("\n")(1))(splitExportResultNLW(4).split("\n")(1))
    }

    test(modelTuple._1 + ": All patch values exported correctly?") {
      assertResult(splitExportResultNLD(4).split("\n").slice(2, 3))(
        splitExportResultNLW(4).split("\n").slice(2, 3))
    }

    test(modelTuple._1 + ": Link variables exported correctly?") {
      assertResult(splitExportResultNLD(5).split("\n")(1))(splitExportResultNLW(5).split("\n")(1))
    }

    test(modelTuple._1 + ": All link values exported correctly?") {
      assertResult(splitExportResultNLD(5).split("\n").slice(2, 3))(
        splitExportResultNLW(5).split("\n").slice(2, 3))
    }

    test(modelTuple._1 + ": All plot globals exported correctly?") {
      assertResult(splitExportResultNLD(6).split("\n"))(
        splitExportResultNLW(6).split("\n"))
    }

    if (splitExportResultNLD.length > 7) {
      if (splitExportResultNLW.length > 7) {
        test(modelTuple._1 + ": All plots exported correctly?") {
          assertResult(splitExportResultNLD(7).split("\n"))(
            splitExportResultNLW(7).split("\n"))
        }
      }
    }
  }
}
