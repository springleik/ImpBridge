''' File: measure.py
    Performs hardware-dependent measurement.
    Implements AC Bridge using Python Audio.
    Originated by M. Williamsen, 2 January 2021.
    http://www.williamsonic.com/ImpBridge/index.html
'''

import wave, math, struct, os.path, json, time
import pyaudio, math, sys

# set some global values
pa = pyaudio.PyAudio()              # Python Audio subsystem
stimWave = None                     # stimulus wave file
respWave = None                     # response wave file
pTree = {}                          # measurement parameter tree
omega = 0.0                         # angular frequency, radians/sample

# initialize default values in parameter tree
def setDefaultParams():
    pTree.clear()
    pTree.update({
        'sampRate':  48000, # samples per second
        'freqHz':    100.0, # cycles per second
        'leftAmpl':  12000, # left channel amplitude
        'rightAmpl': 12000, # right channel amplitude
        'phaseN':        0, # right phase offset in samples
        'quietS':     4800, # quiet time in samples
        'exciteS':    9600, # excitation time in samples
        'numCyc':       20, # number of excitation cycles
        'numPts':        1, # measurements per iteration
        'fName':    'setUp' # name to use for disk files
    })

setDefaultParams()

# check for command line argument
if 1 < len(sys.argv):
	pTree['fName'] = sys.argv[1]

# look for setup file, merge contents if found
def loadParamTree():
    if os.path.exists(pTree['fName'] + '.json'):
        with open(pTree['fName'] + '.json', 'r') as qFile:
            qTree = json.load(qFile)
            if qTree: pTree.update(qTree)

loadParamTree()

def fitParams():
    global omega
    # set arbitrary limits on frequency
    if pTree['freqHz'] < 10.0: pTree['freqHz'] = 10.0
    if pTree['freqHz'] > 10000.0: pTree['freqHz'] = 10000.0

    # fit quarter wavelength to sample rate
    waveLen = 4 * (round(pTree['sampRate'] / pTree['freqHz'] / 4))
    pTree['freqHz'] = pTree['sampRate'] / waveLen

    # fit number of cycles to excitation
    pTree['numCyc'] = math.ceil(pTree['exciteS'] / waveLen)
    if pTree['numCyc'] < 4: pTree['numCyc'] = 4
    pTree['exciteS'] = pTree['numCyc'] * waveLen
    pTree['durationS'] = 2 * pTree['quietS'] + 2 * pTree['exciteS']
    omega = 2.0 * math.pi * pTree['freqHz'] / pTree['sampRate']

fitParams()
print (json.dumps(pTree, indent = 2))

def saveParamTree():
    # create or overwrite setup file
    # print (json.dumps(pTree, indent = 2))
    with open(pTree['fName'] + '.json', 'w') as qFile:
        json.dump(pTree, qFile, indent = 2)

# compute a frame of stimulus
def getFrame():
    a = b = 0
    # initial quiet time
    if   playCall.n < pTree['quietS']:
        getFrame.n = 0

    # left channel tone burst
    elif playCall.n < (pTree['quietS'] + pTree['exciteS']):
        a = round(pTree['leftAmpl'] * math.sin((getFrame.n + 0.5) * omega))
        getFrame.n += 1
        
    # inter-burst quiet time
    elif playCall.n < (2 * pTree['quietS'] + pTree['exciteS'] - pTree['phaseN']):
        getFrame.n = 0

    # right channel tone burst
    elif playCall.n < (2 * pTree['quietS'] + 2 * pTree['exciteS'] - pTree['phaseN']):
        b = round(pTree['rightAmpl'] * math.sin((getFrame.n + 0.5) * omega))
        getFrame.n += 1
    return a, b
    
getFrame.n = 0

# play callback computes stimulus waveform
def playCall(in_data, frame_count, time_info, status_flags):
    frames = bytes()
    theFlag = pyaudio.paContinue
    for i in range(frame_count):
        frames += struct.pack('<hh', *getFrame())
        playCall.n += 1
        if playCall.n == pTree['durationS']:
            theFlag = pyaudio.paComplete
            break
    stimWave.writeframes(frames)
    return (frames, theFlag)
    
playCall.n = 0

# record callback captures response waveform
def recCall(in_data, frame_count, time_info, status_flags):
    theFlag = pyaudio.paContinue
    if pTree['durationS'] < (recCall.n + frame_count):
        nFrames = pTree['durationS'] - recCall.n
        recCall.n += nFrames
        nBytes = nFrames * (len(in_data) // frame_count)
        respWave.writeframes(in_data[:nBytes])
        theFlag = pyaudio.paComplete
    else:
        respWave.writeframes(in_data)
        recCall.n += frame_count
    return (bytes(), theFlag)
    
recCall.n = 0

# send stimulus to stereo output
playStream = pa.open(
    format = pyaudio.paInt16,
    channels = 2,
    rate = pTree['sampRate'],
    frames_per_buffer = 1024,
    stream_callback = playCall,
    output = True,
    start = False)

# receive response from monaural input
recStream = pa.open(
    format = pyaudio.paInt16,
    channels = 1,
    rate = pTree['sampRate'],
    frames_per_buffer = 1024,
    stream_callback = recCall,
    input = True,
    start = False)

# wait for analog circuits to settle
time.sleep(1.0)

# check latency
inLate = recStream.get_input_latency()
outLate = playStream.get_output_latency()
print (' Input latency: {0:.8f} \nOutput latency: {1:.8f}'.format(inLate, outLate))

# start streaming and writing disk files
def startStreaming():
    global stimWave, respWave
    # set up disk output files (wave library only supports uncompressed PCM format)
    stimWave = wave.open(pTree['fName'] + '-stim.wav', 'wb')
    stimWave.setparams((2, 2, pTree['sampRate'], pTree['durationS'], 'NONE', ''))
    respWave = wave.open(pTree['fName'] + '-resp.wav', 'wb')
    respWave.setparams((1, 2, pTree['sampRate'], pTree['durationS'], 'NONE', ''))
    
    # iterate over number of measurements
    for m in range(pTree['numPts']):
        playCall.n = recCall.n = 0
        playStream.start_stream()
        
        # delay recording to account for latency
        time.sleep(1.2 * (inLate + outLate))
        recStream.start_stream()

        # check CPU load
        print ('      CPU load: {0:.8f}'.format(playStream.get_cpu_load()))
        
        # let other threads run
        while playStream.is_active(): time.sleep(0.1)

        # stop streaming
        recStream.stop_stream()
        playStream.stop_stream()
        print ('  Record count: {0}'.format(recCall.n))
        print ('Playback count: {0}'.format(playCall.n))

    # close disk files
    respWave.close()
    stimWave.close()

# create synthetic output for test purposes, write to files
def synthOutput():
    global stimWave, respWave
    # set up disk output files
    stimWave = wave.open(pTree['fName'] + '-stim.wav', 'wb')
    stimWave.setparams((2, 2, pTree['sampRate'], pTree['durationS'], 'NONE', ''))
    respWave = wave.open(pTree['fName'] + '-resp.wav', 'wb')
    respWave.setparams((1, 2, pTree['sampRate'], pTree['durationS'], 'NONE', ''))
    
    # iterate over number of measurements
    for m in range(pTree['numPts']):
        playCall.n = recCall.n = 0
        for n in range(pTree['durationS']):            
            # write disk files
            aFrame = getFrame()
            stimWave.writeframes(struct.pack('<hh', *aFrame))
            respWave.writeframes(struct.pack('<h', sum(aFrame)))
            playCall.n += 1
            
    # close disk files
    respWave.close()
    stimWave.close()

# main control loop
done = False
while not done:
    # prompt user for input
    cmd = input("AcBridge: ")
    
    # commands without arguments
    if ("quit" == cmd) or ("exit" == cmd): done = True
    elif "fit" == cmd: fitParams()
    elif "load" == cmd: loadParamTree()
    elif "reset" == cmd: setDefaultParams()
    elif "save" == cmd: saveParamTree()
    elif "show" == cmd: print (json.dumps(pTree, indent = 2))
    elif "run" == cmd:
        print (' Running: {0}'.format(pTree['fName']))
        fitParams()
        saveParamTree()
        startStreaming()
    elif "synth" == cmd:
        print (' Synthesizing: {0}'.format(pTree['fName']))
        fitParams()
        saveParamTree()
        synthOutput()
    elif ("help" == cmd) or ("?" == cmd):
        print ('Commands available at AcBridge prompt:')
        print (' exit  -- exit this program')
        print (' fit   -- fit measurement parameters to sample rate')
        print (' help  -- present this list')
        print (' load  -- load parameter tree from disk')
        print (' quit  -- quit this program')
        print (' reset -- set all parameters to defaults')
        print (' run   -- start streaming and capturing data')
        print (' save  -- save parameter tree to disk')
        print (' show  -- display parameter tree as JSON')
        print (' synth -- synthesize measurment file')
        
    # look for space-separated key-value pairs
    # key names are case-sensitive
    # string values must be in double quotes
    elif (' ' in cmd):
        key, value = cmd.split(' ', 1)
        try:
            pTree.update(json.loads('{{"{0}":{1}}}'.format(key, value)))
        except ValueError as e:
            print ('Failed to parse key-value pair: {0}'.format(cmd))
    
    # failed to parse command
    else:
        print ('Failed to parse cmd: {0}'.format(cmd))
    
# clean up and exit
recStream.close()
playStream.close()
pa.terminate()
