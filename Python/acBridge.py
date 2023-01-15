''' File: acBridge.py
    Performs hardware-dependent measurement.
    Implements AC Bridge using Python Audio.
    Originated by M. Williamsen, 2 January 2021.
    http://www.williamsonic.com/ImpBridge/index.html
    Leveling and nulling implemented, as of 30 April 2022.
    See Linear Technology App Note 43, Jim Williams, June 1990.
'''

import math, cmath, json, matplotlib.pyplot as plot
import os.path, pyaudio, struct, sys, time, wave

# set some global values
pa = pyaudio.PyAudio()      # Python Audio subsystem
stimWave = None             # stimulus wave file
respWave = None             # response wave file
pTree = {}                  # measurement parameter tree
omega = 0.0                 # angular frequency, radians/sample

# initialize default values in parameter tree
# TODO some params should allow complex values
def setDefaultParams():
    pTree.clear()
    pTree.update({
        'rateS':     48000, # samples per second
        'quietS':     9600, # quiet time in samples
        'timeS':      9600, # excitation time in samples
        'freqHz':    160.0, # cycles per second
        'leftA':     12000, # left channel amplitude, first burst
        'rightA':        0, # right channel amplitude, first burst
        'phaseA':        0, # phase difference, first burst
        'leftB':         0, # left channel amplitude, second burst
        'rightB':    12000, # right channel amplitude, second burst
        'phaseB':        0, # phase difference, second burst
        'numPts':        1, # measurements per iteration
        'fName':   'setUp', # name to use for disk files
        'zRef':      100e6, # reference impedance (assume resistance for now)
        'level':     False, # enable amplitude leveling
        'null':      False, # enable null to balance bridge
        'ref':       False  # use reference value to calculate unknown
    })

# start with default setup
setDefaultParams()

# look for parameter tree file
def loadParamTree(cmd):
    # modify file name if passed in
    if ' ' in cmd:
        load, arg = cmd.split(' ', 1)
        pTree['fName'] = arg

    # load and merge file if found
    qName = pTree['fName'] + '.json'
    if os.path.exists(qName):
        with open(qName, 'r') as qFile:
            print ('Loading setup file: {0}'.format(qName))
            qTree = json.load(qFile)
            if qTree: pTree.update(qTree)

# check for command line argument
if 1 < len(sys.argv):
    loadParamTree('load ' + sys.argv[1])

# apply constraints to measurement parameters
def fitParams():
    global omega
    # set arbitrary limits on frequency
    if pTree['freqHz'] < 10.0: pTree['freqHz'] = 10.0
    if pTree['freqHz'] > 10000.0: pTree['freqHz'] = 10000.0

    # fit quarter wavelength to sample rate
    waveLen = 4 * (round(pTree['rateS'] / pTree['freqHz'] / 4))
    pTree['freqHz'] = pTree['rateS'] / waveLen

    # fit number of cycles to excitation
    pTree['numCyc'] = math.ceil(pTree['timeS'] / waveLen)
    if pTree['numCyc'] < 4: pTree['numCyc'] = 4
    pTree['timeS'] = pTree['numCyc'] * waveLen
    pTree['elapseS'] = 2 * pTree['quietS'] + 2 * pTree['timeS']
    omega = 2.0 * math.pi * pTree['freqHz'] / pTree['rateS']
    
    # set arbitrary limits on amplitude
    pTree['leftA']  = min(32000, pTree['leftA'])
    pTree['rightA'] = min(32000, pTree['rightA'])
    pTree['leftB']  = min(32000, pTree['leftB'])
    pTree['rightB'] = min(32000, pTree['rightB'])

fitParams()

# write parameter tree to disk
def saveParamTree(cmd):
    # modify file name if passed in
    if ' ' in cmd:
        save, arg = cmd.split(' ', 1)
        pTree['fName'] = arg

    # create or overwrite setup file
    with open(pTree['fName'] + '.json', 'w') as qFile:
        json.dump(pTree, qFile, indent = 2)
        qFile.write('\n')

# compute a frame of stimulus
def getFrame():
    a = b = 0
    # initial quiet time
    if   playCall.n < pTree['quietS']:
        getFrame.n = 0

    # first tone burst
    elif playCall.n < (pTree['quietS'] + pTree['timeS']):
        signal = cmath.exp(complex(0, (getFrame.n + 0.5) * omega))
        phase = cmath.exp(complex(0, pTree['phaseA'] / 2.0))
        a = round(pTree['leftA']  * (signal * phase).imag)
        b = round(pTree['rightA'] * (signal / phase).imag)
        getFrame.n += 1
        
    # inter-burst quiet time
    elif playCall.n < (2 * pTree['quietS'] + pTree['timeS']):
        getFrame.n = 0

    # second tone burst
    elif playCall.n < (2 * pTree['quietS'] + 2 * pTree['timeS']):
        signal = cmath.exp(complex(0, (getFrame.n + 0.5) * omega))
        phase = cmath.exp(complex(0, pTree['phaseB'] / 2.0))
        a = round(pTree['leftB']  * (signal * phase).imag)
        b = round(pTree['rightB'] * (signal / phase).imag)
        getFrame.n += 1
        
    # shouldn't reach here
    else:
        print ("Shouldn't reach here.")
    return a, b

# static function variable
getFrame.n = 0

# play callback computes stimulus waveform
def playCall(in_data, frame_count, time_info, status_flags):
    frames = bytes()
    theFlag = pyaudio.paContinue
    for i in range(frame_count):
        frames += struct.pack('<hh', *getFrame())
        playCall.n += 1
        if playCall.n == pTree['elapseS']:
            theFlag = pyaudio.paComplete
            break
    stimWave.writeframes(frames)
    return (frames, theFlag)
    
# static function variable
playCall.n = 0

# record callback captures response waveform
def recCall(in_data, frame_count, time_info, status_flags):
    theFlag = pyaudio.paContinue
    if pTree['elapseS'] < (recCall.n + frame_count):
        nFrames = pTree['elapseS'] - recCall.n
        recCall.n += nFrames
        nBytes = nFrames * (len(in_data) // frame_count)
        respWave.writeframes(in_data[:nBytes])
        theFlag = pyaudio.paComplete
    else:
        respWave.writeframes(in_data)
        recCall.n += frame_count
    return (bytes(), theFlag)

# static function variable
recCall.n = 0

# send stimulus to stereo output
playStream = pa.open(
    format = pyaudio.paInt16,
    channels = 2,
    rate = pTree['rateS'],
    frames_per_buffer = 1024,
    stream_callback = playCall,
    output = True,
    start = False)

# receive response from stereo input
recStream = pa.open(
    format = pyaudio.paInt16,
    channels = 2,
    rate = pTree['rateS'],
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
    stimWave.setparams((2, 2, pTree['rateS'], pTree['elapseS'], 'NONE', ''))
    respWave = wave.open(pTree['fName'] + '-resp.wav', 'wb')
    respWave.setparams((2, 2, pTree['rateS'], pTree['elapseS'], 'NONE', ''))
    
    # iterate over number of measurements
    for m in range(pTree['numPts']):
        playCall.n = recCall.n = 0
        playStream.start_stream()
        
        # delay recording to account for latency
        time.sleep(1.2 * (inLate + outLate))
        recStream.start_stream()
        print ('      CPU load: {0:.8f}'.format(playStream.get_cpu_load()))

        # stop playback stream
        while playStream.is_active(): time.sleep(0.1)
        playStream.stop_stream()
        print ('Playback count: {0}'.format(playCall.n))

        # stop record stream
        while recStream.is_active(): time.sleep(0.1)
        recStream.stop_stream()
        print ('  Record count: {0}'.format(recCall.n))

    # close disk files
    respWave.close()
    stimWave.close()

# create synthetic output for test purposes, write to disk
def synthOutput():
    global stimWave, respWave
    # set up disk output files
    stimWave = wave.open(pTree['fName'] + '-stim.wav', 'wb')
    stimWave.setparams((2, 2, pTree['rateS'], pTree['elapseS'], 'NONE', ''))
    respWave = wave.open(pTree['fName'] + '-resp.wav', 'wb')
    respWave.setparams((2, 2, pTree['rateS'], pTree['elapseS'], 'NONE', ''))
    
    # iterate over number of measurements
    for m in range(pTree['numPts']):
        playCall.n = recCall.n = 0
        for n in range(pTree['elapseS']):            
            # write disk files
            theFrame = getFrame()
            stimWave.writeframes(struct.pack('<hh', *theFrame))
            respWave.writeframes(struct.pack('<hh', *theFrame))
            playCall.n += 1
            
    # close disk files
    respWave.close()
    stimWave.close()

# obtain measurement output
def measResponse(cmd):
    print (' Running: {0}'.format(pTree['fName']))
    fitParams()
    saveParamTree(cmd)
    startStreaming()

# obtain synthetic output
def synthGenerate(cmd):
    print (' Synthesizing: {0}'.format(pTree['fName']))
    fitParams()
    saveParamTree(cmd)
    synthOutput()

# return dot product of two vectors
def dotPrdt(vec1, vec2):
    return sum([vec1[n] * vec2[n] for n in range(len(vec1))])

def studyResponse():
    # update omega in radians/sample
    global omega
    omega = 2.0 * math.pi * pTree['freqHz'] / pTree['rateS']
    print ('   Omega: {0:.8f} rad/samp.'.format(omega))

    # read measurement file into array
    mSeries = []
    nSeries = []
    rName = pTree['fName'] + '-resp.wav'
    if os.path.exists(rName):
        with wave.open(rName, 'rb') as mFile:
            (nchannels, sampwidth, framerate, nframes, comptype, compname) = mFile.getparams()
            while True:
                frame = mFile.readframes(1)
                if not len(frame): break
                sample = struct.unpack('<hh', frame)
                mSeries.append(sample[0])
                nSeries.append(sample[1])
        print ('Measurement file "{0}" has {1} samples.'.format(rName, len(mSeries)))
    else:
        print ('Measurement file "{0}" not found.'.format(rName))
        quit ()

    # obtain amplitudes via inner product with cosine reference
    refCyc = round(pTree['numCyc'] / 2)
    burstRange = pTree['timeS'] * refCyc // pTree['numCyc']
    refVec = [cmath.exp(complex(0, (n + 0.5) * omega)).real for n in range(burstRange)]
    squareNorm = dotPrdt(refVec, refVec)
    halfPi = pTree['timeS'] // pTree['numCyc'] // 4
    thePlot = thePlots = None
    if (1 < pTree['numPts']): figure, thePlots = plot.subplots(pTree['numPts'])
    else: figure, thePlot = plot.subplots()
    startOffs = 0
    for n in range(pTree['numPts']):
        # compute offsets for first burst
        beginIA = startOffs + pTree['quietS'] + (pTree['timeS'] // 4)
        endIA   = beginIA + burstRange
        beginQA = beginIA + halfPi
        endQA   = endIA + halfPi

        # compute offsets for second burst
        beginIB = startOffs + (pTree['quietS'] * 2) + pTree['timeS'] * 5 // 4
        endIB   = beginIB + burstRange
        beginQB = beginIB + halfPi
        endQB   = endIB + halfPi
        
        vectorIA = mSeries[beginIA: endIA]
        vectorQA = mSeries[beginQA: endQA]
        vectorIB = mSeries[beginIB: endIB]
        vectorQB = mSeries[beginQB: endQB]
        vectorM  = mSeries[startOffs: (startOffs + pTree['elapseS'])]
        
        vectorIC = nSeries[beginIA: endIA]
        vectorQC = nSeries[beginQA: endQA]
        vectorID = nSeries[beginIB: endIB]
        vectorQD = nSeries[beginQB: endQB]
        vectorN  = nSeries[startOffs: (startOffs + pTree['elapseS'])]

        # compute in-phase and quadrature components for each burst
        dotPrdtIA = dotPrdt(vectorIA, refVec)
        dotPrdtQA = dotPrdt(vectorQA, refVec)
        dotPrdtIB = dotPrdt(vectorIB, refVec)
        dotPrdtQB = dotPrdt(vectorQB, refVec)
        
        dotPrdtIC = dotPrdt(vectorIC, refVec)
        dotPrdtQC = dotPrdt(vectorQC, refVec)
        dotPrdtID = dotPrdt(vectorID, refVec)
        dotPrdtQD = dotPrdt(vectorQD, refVec)

        # combine into complex values for each burst
        dotPrdtA = complex(dotPrdtIA, -dotPrdtQA) / squareNorm
        dotPrdtB = complex(dotPrdtIB, -dotPrdtQB) / squareNorm

        dotPrdtC = complex(dotPrdtIC, -dotPrdtQC) / squareNorm
        dotPrdtD = complex(dotPrdtID, -dotPrdtQD) / squareNorm
            
        # plot measured response
        if (thePlot):
            thePlot.plot(list(range(0, pTree['elapseS'])), vectorN, '.')
            thePlot.plot(list(range(0, pTree['elapseS'])), vectorM, '.')
        else:
            thePlots[n].plot(list(range(0, pTree['elapseS'])), vectorN, '.')
            thePlots[n].plot(list(range(0, pTree['elapseS'])), vectorM, '.')

        # plot fitted response for first burst
        fitBurstA = [(dotPrdtA * cmath.exp(complex(0, (x + 0.5) * omega))).real for x in range(burstRange + halfPi)]
        fitBurstC = [(dotPrdtC * cmath.exp(complex(0, (x + 0.5) * omega))).real for x in range(burstRange + halfPi)]
        if (thePlot):
            thePlot.plot(list(range(beginIA, endQA)), fitBurstA, '-')
            thePlot.plot(list(range(beginIA, endQA)), fitBurstC, '-')
        else:
            thePlots[n].plot(list(range(beginIA-startOffs, endQA-startOffs)), fitBurstA, '-')
            thePlots[n].plot(list(range(beginIA-startOffs, endQA-startOffs)), fitBurstC, '-')
        
        # plot fitted response for second burst
        fitBurstB = [(dotPrdtB * cmath.exp(complex(0, (x + 0.5) * omega))).real for x in range(burstRange + halfPi)]
        fitBurstD = [(dotPrdtD * cmath.exp(complex(0, (x + 0.5) * omega))).real for x in range(burstRange + halfPi)]
        if (thePlot):
            thePlot.plot(list(range(beginIB, endQB)), fitBurstB, '-')
            thePlot.plot(list(range(beginIB, endQB)), fitBurstD, '-')
        else:
            thePlots[n].plot(list(range(beginIB-startOffs, endQB-startOffs)), fitBurstB, '-')
            thePlots[n].plot(list(range(beginIB-startOffs, endQB-startOffs)), fitBurstD, '-')

        # calculate impedance ratio
        print ('      MA: {0:.8f}'.format(dotPrdtA))
        print ('      MB: {0:.8f}'.format(dotPrdtB))
        print ('      MC: {0:.8f}'.format(dotPrdtC))
        print ('      MD: {0:.8f}'.format(dotPrdtD))
        phaseA = cmath.exp(complex(0, pTree['phaseA'] / 2.0))
        phaseB = cmath.exp(complex(0, pTree['phaseB'] / 2.0))
        zRatio = ((pTree['leftA'] * phaseA * dotPrdtB - pTree['leftB'] * phaseB * dotPrdtA) /
            (pTree['rightB'] / phaseB * dotPrdtA - pTree['rightA'] / phaseA * dotPrdtB))
        print ('  zRatio: {0:.8f}'.format(zRatio))
        pTree['zRatio'] = cmath.polar(zRatio)
        
        # proceed to next measurement
        startOffs += pTree['elapseS']
                
    # show all
    plot.show()
    
    # check leveling after last measurement
    # TODO try leveling etc. within one measurement
    if 'level' in pTree and pTree['level']:
        absA = abs(dotPrdtA)
        absB = abs(dotPrdtB)
        pTree['leftA']  = pTree['leftA']  * 12000.0 / absA
        pTree['rightB'] = pTree['rightB'] * 12000.0 / absB
        if 32000 < pTree['leftA']:
            pTree['rightB'] = 32000.0 * pTree['rightB'] / pTree['leftA']
            pTree['leftA']  = 32000
        if 32000 < pTree['rightB']:
            pTree['leftA']  = 32000.0 * pTree['leftA'] / pTree['rightB']
            pTree['rightB'] = 32000

    # given an impedance ratio, compute excitation to null the bridge
    if 'null' in pTree and pTree['null']:
        magn = abs(zRatio)
        pTree['phaseA'] = cmath.phase(zRatio)
        pTree['leftA'] = pTree['rightA'] = 12000
        if magn > 1.0:
            pTree['rightA'] = -12000 / magn
        else:
            pTree['leftA'] = -12000 * magn
            
        # ignore second burst in this case
        pTree['leftB'] = pTree['rightB'] = pTree['phaseB'] = 0
        
    # given an impedance ratio and reference impedance, compute the unknown impedance
    # TODO consider complex reference impedance
    if 'ref' in pTree and pTree['ref']:
        # get reference resistance from parameter tree
        z1 = cmath.rect(pTree['zRef'], 0.0)
        z2 = z1 / zRatio
        print ('Ref  z1: {0}, z2: {1}'.format(z1, z2))

        # compute unknown parallel resistance and capacitance
        y2 = 1.0 / z2
        r2 = 1.0 / y2.real
        c2 = y2.imag / 2.0 / math.pi / pTree['freqHz']
        print ('Meas r2: {0}, c2: {1}'.format(r2, c2))
                
    # replace z2 with a short circuit to calibrate detector gain and phase
    # assumes right input is connected directly to right output
    if 'cal' in pTree and pTree['cal']:
        # find detector gain as a complex value
        detGain = dotPrdtB / dotPrdtD
        pTree['detGain'] = cmath.polar(detGain)
        print (' detGain: {0:.8f}'.format(detGain))
        
        # find excitation gain as an absolute value
        # TODO may include phase later
        excGain = abs(dotPrdtD) / pTree['rightB']
        pTree['excGain'] = excGain
        print (' excGain: {0:.8f}'.format(excGain))
        
    # replace z2 with an open circuit to obtain ratio of zDet/z1
    # assumes right input is connected directly to right output
    if 'det' in pTree and pTree['det']:
        # find excitation vector
        excLeft = pTree['leftA'] * cmath.rect(pTree['excGain'], cmath.phase(dotPrdtD))
        
        # compute detector impedance
        detLeft = dotPrdtA / cmath.rect(*(pTree['detGain']))
        zDetRatio = detLeft / (excLeft - detLeft)
        z1 = cmath.rect(pTree['zRef'], 0.0)
        zDet = z1 * zDetRatio
        print ('zDet: {0}'.format(zDet))

        # compute detector parallel resistance and capacitance
        yDet = 1.0 / zDet
        rDet = 1.0 / yDet.real
        cDet = yDet.imag / 2.0 / math.pi / pTree['freqHz']
        print ('Meas rDet: {0}, cDet: {1}'.format(rDet, cDet))
        
def showHelp():
    print ('Commands available at acBridge prompt:')
    print (' calc  -- analyze measured response')
    print (' done  -- exit this program')
    print (' fit   -- fit measurement parameters to sample rate')
    print (' help  -- present this list')
    print (' load  -- load parameter tree from disk')
    print (' meas  -- start streaming and capturing data')
    print (' new   -- set default parameters')
    print (' save  -- save parameter tree to disk')
    print (' show  -- display parameter tree as JSON')
    print (' synth -- synthesize measurment file')
    
    print ('Keynames that control measurement:')
    print (' level -- enables excitation leveling if true')
    print (' null  -- enables bridge nulling if true')
    print (' ref   -- compute unknown impedance from reference if true')
    print (' cal   -- calibrate detector gain and phase if true')
    print (' det   -- compute detector impedance if true')

# main control loop
done = False
while not done:
    # prompt user for input
    cmd = input("acBridge: ")
    
    # commands, some with arguments
    if   not cmd.find('calc'):  studyResponse()
    elif not cmd.find('done'):  done = True
    elif not cmd.find('fit'):   fitParams()
    elif not cmd.find('help'):  showHelp()
    elif not cmd.find('load'):  loadParamTree(cmd)
    elif not cmd.find('meas'):  measResponse(cmd)
    elif not cmd.find('new'):   setDefaultParams()
    elif not cmd.find('save'):  saveParamTree(cmd)
    elif not cmd.find('show'):  print (json.dumps(pTree, indent = 2))
    elif not cmd.find('synth'): synthGenerate(cmd)
    elif not cmd.find('?'):     showHelp()
    
    # look for space-separated key-value pairs
    # key names are case-sensitive, put string values in double quotes
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
