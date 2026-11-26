import librosa, numpy as np, json, sys
from scipy.signal import find_peaks
key=sys.argv[1];A=json.load(open(f'{key}/analyse.json'))
y,sr=librosa.load(f'{key}/mono.wav',sr=22050)
beats=np.array(A['beats']);bars=beats[::4]
bf=librosa.time_to_frames(bars,sr=sr,hop_length=512)
C=librosa.feature.chroma_cqt(y=y,sr=sr,hop_length=512);M=librosa.feature.mfcc(y=y,sr=sr,n_mfcc=13,hop_length=512)
R=librosa.feature.rms(y=y,hop_length=512)
X=np.vstack([librosa.util.normalize(librosa.util.sync(C,bf),axis=0),librosa.util.normalize(librosa.util.sync(M,bf)[1:],axis=0),librosa.util.sync(R,bf)*8])
X=X[:,1:len(bars)]  # colonne i = mesure i
S=np.corrcoef(X.T);n=S.shape[0];k=8
ker=np.kron(np.array([[1,-1],[-1,1]]),np.ones((k,k)))*np.outer(np.hanning(2*k),np.hanning(2*k))
nov=np.zeros(n)
for i in range(k,n-k):nov[i]=(S[i-k:i+k,i-k:i+k]*ker).sum()
pk,_=find_peaks(nov,distance=4)
cand=[(bars[i],nov[i]) for i in pk if 70<=bars[i]<=125]
# phrases de 4 mesures depuis la première mesure
print(key,'frontières candidates',[(round(t,1),round(v,2)) for t,v in sorted(cand,key=lambda c:-c[1])[:5]])
print('  toutes',[round(bars[i],1) for i in pk])
