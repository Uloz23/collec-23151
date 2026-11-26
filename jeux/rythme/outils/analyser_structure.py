import librosa, numpy as np, json, sys, subprocess, os
SONGS={'bordels':'bee9bb3c-Monome_de_Bordels','birse':'e9cd1eaf-Monome_de_birse_Cover','boquette':'2de62156-Monome_de_boquette_','cluns':'397d764b-Monome_de_cluns__','chalons':'952c427e-Avec_ma_cousine_Lison_'}
key=sys.argv[1];src=f'/mnt/user-data/uploads/{SONGS[key]}.mp3'
os.makedirs(key,exist_ok=True)
wav=f'{key}/mono.wav'
if not os.path.exists(wav):subprocess.run(['ffmpeg','-y','-loglevel','error','-i',src,'-vn','-ac','1','-ar','22050',wav],check=True)
y,sr=librosa.load(wav,sr=22050);dur=len(y)/sr
tempo,beats=librosa.beat.beat_track(y=y,sr=sr,units='time',trim=False)
tempo=float(np.atleast_1d(tempo)[0]);ib=np.diff(beats)
print(key,'durée',round(dur,1),'tempo',round(tempo,1),'beats',len(beats),'écart',round(float(np.median(ib)),3),'σ',round(float(ib.std()),3))
# structure : chroma + mfcc synchronisés sur les mesures (4 temps)
bfr=librosa.time_to_frames(beats,sr=sr,hop_length=512)
C=librosa.feature.chroma_cqt(y=y,sr=sr,hop_length=512);M=librosa.feature.mfcc(y=y,sr=sr,n_mfcc=13,hop_length=512)
rms=librosa.feature.rms(y=y,hop_length=512)[0]
bars=bfr[::4]
Cs=librosa.util.sync(C,bars);Ms=librosa.util.sync(M,bars);Rs=librosa.util.sync(rms[None],bars)[0]
X=np.vstack([librosa.util.normalize(Cs,axis=0),librosa.util.normalize(Ms[1:],axis=0)*.7])
bt=np.r_[0,beats[::4]][:X.shape[1]]
k=max(4,min(10,int(dur/22)))
bnd=librosa.segment.agglomerative(X,k)
seg=[(int(bnd[i]),int(bnd[i+1]) if i+1<len(bnd) else X.shape[1]) for i in range(len(bnd))]
# similarité entre segments pour étiqueter
feats=[X[:,a:b].mean(1) for a,b in seg]
lab=[];L=[]
for f in feats:
    best=None
    for j,g in enumerate(L):
        s=np.dot(f,g)/np.linalg.norm(f)/np.linalg.norm(g)
        if s>.985 and (best is None or s>best[0]):best=(s,j)
    if best:lab.append(best[1])
    else:L.append(f);lab.append(len(L)-1)
out=[]
for (a,b),l in zip(seg,lab):
    t0=float(bt[a]) if a<len(bt) else dur;t1=float(bt[b]) if b<len(bt) else dur
    e=float(Rs[a:b].mean()) if b>a else 0
    out.append(dict(t0=round(t0,2),t1=round(t1,2),lab='ABCDEFGHIJ'[l],e=round(e,4)))
    print(f'  {t0:6.1f}-{t1:6.1f}  {"ABCDEFGHIJ"[l]}  énergie {e:.3f}')
json.dump(dict(dur=dur,tempo=tempo,beats=[round(float(b),3) for b in beats],segs=out),open(f'{key}/analyse.json','w'))
