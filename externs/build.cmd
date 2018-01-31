@echo off
REM call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
call "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat"
cl /I..\..\hashlink\src /I..\godot_headers /c hlgodot.c
link /DLL /OUT:..\project\hlgodot.hdll hlgodot.obj ..\..\hashlink\Release\libhl.lib
