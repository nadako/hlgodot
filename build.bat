call "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat"
cl /Igodot_headers /I../hashlink/src /Fogodot.obj  /c godot.c
