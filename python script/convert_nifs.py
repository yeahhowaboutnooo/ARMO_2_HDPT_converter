#!/usr/bin/env python3

# ***** BEGIN LICENSE BLOCK *****
#
#Copyright (c) 2021, yeahhowaboutnooo.
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.
#
# ***** END LICENSE BLOCK *****

import sys, os, glob, re

from pyffi.formats.nif import NifFormat
import multiprocessing as mp

# sys.frozen does not exist, unless it's been set by pyinstaller
# -> if it does not exist getattr returns false
if not getattr( sys, 'frozen', False ):
	os.chdir(os.path.dirname(__file__))

#super dirty: windows does not allow \/:*?"<>| in file names
#-> because ':' is fairly common for meshnames -> convert ':' to ';' and disallow ';' instead
#(obviously the xEdit delphi script then does the reverse conversion from ';' to ':')
#and no i don't like this "solution" either :P
#compile this regex here for later use
rec = re.compile(r"[\\\/;\*\?<>\|]")


files = glob.glob('./**/*.[nN][iI][fF]', recursive=True)
#remove previously generated _extraParts from the file-list
extraParts = '__HDPT_extraParts'
files = [f for f in files if extraParts not in f]

#how certain we are that shape is in fact a hairmesh and not a collisionobject
#(otherwise mfgfix/opparco-mfg can bug out, IF the first shape is a collisionobject)
def meshCertainty(shape):
	#shader and alpha property in nifskope
	propCntr = 0
	for prop in shape.bs_properties:
		if prop is not None:
			propCntr += 1
	return propCntr

def convertFile(f):
	data = NifFormat.Data()

	print('reading ' + f + ' ...', flush=True)
	with open(f, 'rb') as stream:
		data.read(stream)
#	print(' done!')

	niTriShapes = []
	for c in data.roots[0].children:
		if type(c) is NifFormat.NiTriShape:
			niTriShapes.append(c)
			match = rec.search(c.name.decode('utf-8'))
			if match:
				raise Exception('Fatal error: niTriShape \"' + c.name.decode('utf-8') + '\" has illegal character: \'' + match.group() + '\'')

	if len(niTriShapes) <= 0:
		print('WARNING: ' + f + ': no niTriShapes found!', file=sys.stderr)


	#create Dir
	nifDir = f + extraParts
	os.makedirs(nifDir, exist_ok=True)

	#remove_child(child)
	for shape in niTriShapes:
		data.roots[0].remove_child(shape)


	# sort shapes by shader/alpha property count
	# (otherwise facial expressions may stop working)
	niTriShapes.sort(key=meshCertainty, reverse=True)


	#add_child(child)
	for i,shape in enumerate(niTriShapes):
		data.roots[0].add_child(shape)
		shapeFile = nifDir + '/' + str(i).zfill(3) + '_' + shape.name.decode('utf-8').replace(':', ';') + '.nif'
#		print('writing ' + shapeFile + ' ...', end='', flush=True)
		with open(shapeFile, 'wb') as shapeStream:
			data.write(shapeStream)
		data.roots[0].remove_child(shape)
		if i == 0:
			for b in data.roots[0].get_extra_datas():
				if type(b) is NifFormat.NiStringExtraData:
					if b.name.decode('utf-8') == 'HDT Skinned Mesh Physics Object':
						data.roots[0].remove_extra_data(b)
						break
#		print(' done!')

if __name__ == '__main__':
	mp.freeze_support()
	#lower the prio and obey process affinity mask
	try:
		sys.getwindowsversion()
	except AttributeError: #Unix
		os.nice(19)
		poolsize = len(os.sched_getaffinity(0))
	else: #Windows
		os.system("wmic process where processid=\""+str(os.getpid())+"\" CALL   setpriority \"idle\"")

		#thanks to eryksun: https://bugs.python.org/msg236867
		from ctypes import *
		from ctypes.wintypes import *
		
		kernel32 = WinDLL('kernel32')
		
		DWORD_PTR = WPARAM
		PDWORD_PTR = POINTER(DWORD_PTR)
		
		GetCurrentProcess = kernel32.GetCurrentProcess
		GetCurrentProcess.restype = HANDLE
		
		OpenProcess = kernel32.OpenProcess
		OpenProcess.restype = HANDLE
		OpenProcess.argtypes = (DWORD, # dwDesiredAccess,_In_
		                        BOOL,  # bInheritHandle,_In_
		                        DWORD) # dwProcessId, _In_
		
		GetProcessAffinityMask = kernel32.GetProcessAffinityMask
		GetProcessAffinityMask.argtypes = (
		    HANDLE,     # hProcess, _In_
		    PDWORD_PTR, # lpProcessAffinityMask, _Out_
		    PDWORD_PTR) # lpSystemAffinityMask, _Out_
		
		SetProcessAffinityMask = kernel32.SetProcessAffinityMask
		SetProcessAffinityMask.argtypes = (
		  HANDLE,    # hProcess, _In_
		  DWORD_PTR) # dwProcessAffinityMask, _In_
		
		PROCESS_SET_INFORMATION = 0x0200
		PROCESS_QUERY_INFORMATION = 0x0400
		PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
		if sys.getwindowsversion().major < 6:
			PROCESS_QUERY_LIMITED_INFORMATION = PROCESS_QUERY_INFORMATION
		
		def sched_getaffinity(pid):
			if pid == 0:
				hProcess = GetCurrentProcess()
			else:
				hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,
			                           False, pid)
			if not hProcess:
				raise WinError()
			lpProcessAffinityMask = DWORD_PTR()
			lpSystemAffinityMask = DWORD_PTR()
			if not GetProcessAffinityMask(hProcess,
			                              byref(lpProcessAffinityMask),
			                              byref(lpSystemAffinityMask)):
				raise WinError()
			mask = lpProcessAffinityMask.value
			return {c for c in range(sizeof(DWORD_PTR) * 8) if (1 << c) & mask}
		poolsize = len(sched_getaffinity(0))


	print('starting ' + str(poolsize) + ' worker threads')
	p = mp.Pool(poolsize)
	result = p.map_async(convertFile, files, 1)
	try:
		result.get()
	except Exception as error:
		print(error.args[0], file=sys.stderr, flush=True)
	finally:
		p.terminate()
		p.join()
		input('Press Enter to close the program')
