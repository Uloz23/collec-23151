import librosa, numpy as np, json, sys, subprocess
key=sys.argv[1];cut_end=float(sys.argv[2]);title=sys.argv[3]
SONGS={'bordels':'bee9bb3c-Monome_de_Bordels','birse':'e9cd1eaf-Monome_de_birse_Cover','boquette':'2de62156-Monome_de_boquette_','cluns':'397d764b-Monome_de_cluns__','chalons':'952c427e-Avec_ma_cousine_Lison_'}
A=json.load(open(f'{key}/analyse.json'));beats=np.array(A['beats']);dur=A['dur'];tempo=A['tempo']
y,sr=librosa.load(f'{key}/mono.wav',sr=22050);hop=512
S=np.abs(librosa.stft(y,n_fft=2048,hop_length=hop));f=librosa.fft_frequencies(sr=sr,n_fft=2048)
bd={'g':(30,150),'m':(150,2000),'a':(2000,8000)};E={};ons={}
for k,(a,b) in bd.items():
    m=(f>=a)&(f<b);E[k]=S[m].sum(0);E[k]=E[k]/np.percentile(E[k],95)
    env=librosa.onset.onset_strength(S=librosa.amplitude_to_db(S[m]**2+1e-9),sr=sr,hop_length=hop)
    ons[k]=librosa.onset.onset_detect(onset_envelope=env,sr=sr,hop_length=hop,units='time')
rms=librosa.feature.rms(y=y,hop_length=hop)[0];rt=librosa.frames_to_time(np.arange(len(rms)),sr=sr,hop_length=hop)
def energy(t0,t1):
    m=(rt>=t0)&(rt<t1);return rms[m].mean() if m.any() else 0
bar_t=beats[::4];bar_e=np.array([energy(bar_t[i],bar_t[i+1] if i+1<len(bar_t) else dur) for i in range(len(bar_t))])
med=np.median(bar_e[bar_e>0.02]) if (bar_e>0.02).any() else np.median(bar_e)
def barlev(t):
    i=max(0,np.searchsorted(bar_t,t)-1);return bar_e[i]/med
def en(k,t):
    i=min(int(t*sr/hop),len(E[k])-1);return E[k][max(0,i-1):i+3].max()
grid=[]
for i in range(len(beats)-1):grid+=[beats[i],(beats[i]+beats[i+1])/2]
grid=np.array(grid)
def snap(t):
    j=np.argmin(abs(grid-t));return grid[j] if abs(grid[j]-t)<0.07 else None
def build(level):
    cand={}
    for i,t in enumerate(beats):
        if barlev(t)<0.25:continue
        if level=='facile' and i%2:continue
        cand[round(float(t),3)]=1
    if level!='facile':
        keys=['g','m'] if level=='normal' else ['g','m','a']
        for k in keys:
            for t in ons[k]:
                s=snap(t)
                if s is None:continue
                lv=barlev(s)
                if lv<(0.8 if level=='normal' else 0.6):continue
                if en(k,s)>(1.0 if level=='normal' else 0.6):cand[round(float(s),3)]=1
    base={'facile':0.45,'normal':0.26,'difficile':0.17}[level]
    notes=[];last=-9
    for t in sorted(cand):
        gap=base*(0.8 if barlev(t)>1.15 else 1.25 if barlev(t)<0.7 else 1)
        if t-last<gap:continue
        sc={k:en(k,t) for k in E};col={'g':0,'m':1,'a':2}[max(sc,key=sc.get)]
        notes.append([t,col]);last=t
    # équilibrage : jamais 4 de suite sur la même colonne, et rotation douce
    run=0
    for i in range(1,len(notes)):
        run=run+1 if notes[i][1]==notes[i-1][1] else 0
        if run>=3:notes[i][1]=(notes[i][1]+1+(i%2))%3;run=0
    # notes longues : une par phrase de 8 mesures dans les passages soutenus
    per=60/tempo;L={'facile':3,'normal':2,'difficile':2}[level];every={'facile':32,'normal':32,'difficile':16}[level]
    for bi in range(16,len(beats)-8,every):
        bt=beats[bi]
        c=[n for n in notes if abs(n[0]-bt)<0.08 and len(n)==2 and n[1]!=1]
        if not c or barlev(bt)<0.7:continue
        h=c[0];d=round(L*per,3)
        notes=[n for n in notes if not (n[1]==h[1] and h[0]<n[0]<=h[0]+d+0.15)];h.append(d)
    return notes
P={lv:build(lv) for lv in ('facile','normal','difficile')}
src=f'/mnt/user-data/uploads/{SONGS[key]}.mp3'
def save(name,notes,d):
    json.dump({'titre':title,'duree':round(d,2),'tempo':round(tempo,2),'beats':[float(b) for b in beats if b<d],'notes':notes},open(f'{key}/{name}.json','w'),separators=(',',':'))
save('partition_entier',P,dur)
cut=cut_end+1.5
Ps={lv:[n for n in v if n[0]+(n[2] if len(n)>2 else 0)<cut_end-0.2] for lv,v in P.items()}
save('partition_court',Ps,cut)
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',src,'-vn','-ac','2','-b:a','96k',f'{key}/entier.mp3'],check=True)
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',src,'-vn','-t',str(cut),'-af',f'afade=t=out:st={cut_end-0.5}:d=2','-ac','2','-b:a','96k',f'{key}/court.mp3'],check=True)
print(key,'entier',{k:len(v) for k,v in P.items()},'court',{k:len(v) for k,v in Ps.items()},'cut',round(cut,1))
