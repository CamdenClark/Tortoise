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


  private def csvPath(name: String): String =
    s"${Paths.get("").toAbsolutePath}/resources/test/export-world/$name.csv"

}
