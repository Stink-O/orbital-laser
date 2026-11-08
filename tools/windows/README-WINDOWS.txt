Orbital Laser on Windows: test build
====================================

This is a test build. It has only been run under Wine on Linux, never on real Windows, so please report what happens.
Windows may warn that it doesn't know these programs, because they aren't signed. Strikes wreck the land for good. This
folder keeps its own saves in game\, so your Horizon worlds are left alone.

You need
  - Windows 10 or 11, 64-bit, and a graphics card with Vulkan or DirectX 12
  - Minecraft Java Edition 26.3, played once from the official launcher
  - Java 25 (a JDK), with java and javac on the PATH or JAVA_HOME set
  - the 26.3 server.jar: its link is downloads.server.url in
    %APPDATA%\.minecraft\versions\26.3\26.3.json

Setup, once
  Double-click prepare.bat and give it the path to server.jar. It takes a few minutes.

Play
  Double-click play.bat. It opens a creative world called OrbitalTest.
  Type /orbital give for the Designator. Press R with it in hand for the laser wheel, click a laser, then aim
  and hold right-click to fire. The Fold and the Supervolcano are on page 4 of the wheel. The middle of the wheel turns terrain damage off.

If something goes wrong
  Options > Mods says why the mod stopped, if it did. The game's log is
  %APPDATA%\horizon\logs\latest.log. Please send that, what you did, and your graphics card.

Please tell us
  - whether prepare.bat worked
  - whether the Fold and the Supervolcano ran to the end, and whether their craters appeared
  - whether the effects draw with Options > Graphics > Advanced > Graphics API on DirectX 12, and on Vulkan
  - your frame rate during the fold and the eruption
