// (C) Uri Wilensky. https://github.com/NetLogo/Tortoise

package org.nlogo.tortoise
package dock

import java.nio.file.Paths

import org.nlogo.tortoise.tags.SlowTest

class TestImportWorld extends DockingSuite {

  test("Import PD - Fresh", SlowTest) { implicit fixture => import fixture._
    open("models/Sample Models/Social Science/Unverified/Prisoner's Dilemma/PD Two Person Iterated.nlogo", None)
    testCommand(s"""import-world "${csvPath("pd-two-person-iterated")}"""")
  }

  test("Import PD - Clobber", SlowTest) { implicit fixture => import fixture._
    open("models/Sample Models/Social Science/Unverified/Prisoner's Dilemma/PD Two Person Iterated.nlogo", None)
    testCommand("setup")
    testCommand(s"""import-world "${csvPath("pd-two-person-iterated")}"""")
  }

  test("Import Climate Change - Fresh", SlowTest) { implicit fixture => import fixture._
    open("models/Sample Models/Earth Science/Climate Change.nlogo", None)
    testCommand(s"""import-world "${csvPath("climate-change")}"""")
  }

  test("Import Climate Change - Clobber", SlowTest) { implicit fixture => import fixture._
    open("models/Sample Models/Earth Science/Climate Change.nlogo", None)
    testCommand("setup")
    testCommand(s"""import-world "${csvPath("climate-change")}"""")
  }

  private def csvPath(name: String): String =
    s"${Paths.get("").toAbsolutePath}/resources/test/export-world/$name.csv"

}
