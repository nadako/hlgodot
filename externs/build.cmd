@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
cl /I..\..\hashlink\src /I..\godot_headers /c hlgodot.c
link /DLL /OUT:hlgodot.hdll hlgodot.obj

