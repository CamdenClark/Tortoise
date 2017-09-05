package org.nlogo.tortoise
package dock

import tags.SlowTest
import org.nlogo.core.Resource
import scala.io.Source

class TestExportWorld extends DockingSuite {
  for (model <- Model.models) {
    val name = model.name
    test(s"${name}: export-world works") { implicit fixture => import fixture._
      open(model.path, model.dimensions)
      testCommand(s"""export-world (ifelse-value netlogo-web? [ "/tmp/NLW_${name}.csv"] [ "/tmp/NLD_${name}.csv" ])""")
    }
    test(s"${name}: export-world matches") { implicit fixture => import fixture._
      var exportResultNLD = scala.util.Try(Source.fromFile(s"/tmp/NLD_${name}.csv").mkString)
                .getOrElse(s"Could not find NLD ${name}.csv file").trim

      var exportResultNLW = scala.util.Try(Source.fromFile(s"/tmp/NLW_${name}.csv").mkString)
                .getOrElse(s"Could not find NLW ${name}.csv file").trim

      val outputRegex = """"OUTPUT"\n""".r

      exportResultNLD = outputRegex.replaceAllIn(exportResultNLD, "")
      var splitExportResultNLD = exportResultNLD.split("\n\n").toArray
      var splitExportResultNLW = exportResultNLW.split("\n\n").toArray

      assertResult(splitExportResultNLD(1), name + ": Random state exported the same way?")(splitExportResultNLW(1))

      assertResult(splitExportResultNLD(2).split("\n")(1), name + ": Global variables exported correctly?")(splitExportResultNLW(2).split("\n")(1))

      assertResult(splitExportResultNLD(2).split("\n").slice(2, splitExportResultNLD(2).split("\n").length), name + ": All global values exported correctly?")(
        splitExportResultNLW(2).split("\n").slice(2, splitExportResultNLW(2).split("\n").length))

      assertResult(splitExportResultNLD(3).split("\n"), name + ": Turtle variables exported correctly?")(splitExportResultNLW(3).split("\n"))

      assertResult(splitExportResultNLD(3).split("\n").slice(2, splitExportResultNLD(3).split("\n").length), name + ": All turtle values exported correctly?")(
        splitExportResultNLW(3).split("\n").slice(2, splitExportResultNLW(3).split("\n").length))

      assertResult(splitExportResultNLD(4).split("\n")(1), name + ": Patch variables exported correctly?")(splitExportResultNLW(4).split("\n")(1))

      assertResult(splitExportResultNLD(4).split("\n").slice(2, splitExportResultNLD(4).split("\n").length), name + ": All patch values exported correctly?")(
        splitExportResultNLW(4).split("\n").slice(2, splitExportResultNLW(4).split("\n").length))

      assertResult(splitExportResultNLD(5).split("\n")(1), name + ": Link variables exported correctly?")(splitExportResultNLW(5).split("\n")(1))

      assertResult(splitExportResultNLD(5).split("\n").slice(2, splitExportResultNLD(5).split("\n").length), name + ": All link values exported correctly?")(
        splitExportResultNLW(5).split("\n").slice(2, splitExportResultNLW(5).split("\n").length))

      assertResult(splitExportResultNLD(6).split("\n"), name + ": All plot globals exported correctly?")(
        splitExportResultNLW(6).split("\n"))

      if (splitExportResultNLD.length > 7) {
        if (splitExportResultNLW.length > 7) {
            assertResult(splitExportResultNLD.slice(7, splitExportResultNLD.length).mkString("\n\n"), name + ": All plots exported correctly?")(
              splitExportResultNLW.slice(7, splitExportResultNLW.length).mkString("\n\n"))
        }
      }

      assertResult(splitExportResultNLD.slice(1, splitExportResultNLD.length).mkString("\n\n"), name + ": Completely transparent")(
        splitExportResultNLW.slice(1, splitExportResultNLW.length).mkString("\n\n"))
    }
  }
}
