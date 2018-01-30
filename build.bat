call "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat"
mkdir bin
cl /Igodot_headers /I../hashlink/src /Fobin\godot.obj  /c godot.c
cl /LD bin\godot.obj /link /DLL /OUT:bin\godot.dll /IMPLIB:bin\godot.lib
