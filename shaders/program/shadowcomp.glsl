
#include "/settings.glsl"
#include "/lib/voxel/voxel.glsl"

#ifdef PASS_COUNT

    layout(local_size_x=256) in;
    const ivec3 workGroups=ivec3(groupsQuads,1,1);

    void main(){
        uint i=gl_GlobalInvocationID.x;
        if(i >= storeQDCount()) return;
        uint key=morton(storeQDCentroid(vxq.quads[i]),vM(),vMx());
        atomicAdd(vxh.bucketCount[key >> uint(12)],1u);
    }
#endif

#ifdef PASS_SCAN

    layout(local_size_x=1024) in;
    const ivec3 workGroups=ivec3(1,1,1);

    shared uint sSum[2][1024];

    void main(){
        uint t=gl_LocalInvocationID.x;
        const uint PER=uint(262144 / 1024);
        uint base=t*PER;

        uint local=0u;
        for(uint k=0u; k<PER; k++) local += vxh.bucketCount[base+k];

        sSum[0][t]=local;
        memoryBarrierShared();
        barrier();

        int src=0;
        for(uint off=1u; off<1024u; off <<= 1){
            int dst=1-src;
            sSum[dst][t]=sSum[src][t]+((t >= off)?sSum[src][t-off]:0u);
            memoryBarrierShared();
            barrier();
            src=dst;
        }

        uint run=sSum[src][t]-local;
        for(uint k=0u; k<PER; k++){
            vxh.bucketCursor[base+k]=run;
            run += vxh.bucketCount[base+k];
        }
    }
#endif

#ifdef PASS_SCATTER

    layout(local_size_x=256) in;
    const ivec3 workGroups=ivec3(groupsQuads,1,1);

    void main(){
        uint i=gl_GlobalInvocationID.x;
        if(i >= storeQDCount()) return;
        uint key=morton(storeQDCentroid(vxq.quads[i]),vM(),vMx());
        uint pos=atomicAdd(vxh.bucketCursor[key >> uint(12)],1u);
        vxa.sortedKeys[pos]=key;
        vxa.sortedIds[pos]=i;
    }
#endif

#ifdef PASS_SORT

    layout(local_size_x=256) in;
    const ivec3 workGroups=ivec3(1024,1,1);

    void main(){
        uint b=gl_GlobalInvocationID.x;
        if(b >= uint(262144)) return;

        uint cnt=vxh.bucketCount[b];
        if(cnt<=1u) return;

        uint end=vxh.bucketCursor[b];
        uint start=end-cnt;

        if(cnt>1024u){
            uint k=b << uint(12);
            for(uint a=start; a<end; a++) vxa.sortedKeys[a]=k;
            return;
        }

        for(uint a=start+1u; a<end; a++){
            uint k=vxa.sortedKeys[a];
            uint id=vxa.sortedIds[a];
            uint c=a;
            while(c>start&&vxa.sortedKeys[c-1u]>k){
                vxa.sortedKeys[c]=vxa.sortedKeys[c-1u];
                vxa.sortedIds[c]=vxa.sortedIds[c-1u];
                c--;
            }
            vxa.sortedKeys[c]=k;
            vxa.sortedIds[c]=id;
        }
    }
#endif

#ifdef PASS_TREE

    layout(local_size_x=256) in;
    const ivec3 workGroups=ivec3(groupsQuads,1,1);

    int vxDelta(int i,int j,int n){
        if(j<0 || j >= n) return -1;
        uint ki=vxa.sortedKeys[i];
        uint kj=vxa.sortedKeys[j];
        if(ki==kj) return 63-findMSB(uint(i) ^ uint(j));
        return 31-findMSB(ki ^ kj);
    }

    void main(){
        int i=int(gl_GlobalInvocationID.x);
        int n=int(storeQDCount());
        if(i >= n-1) return;

        int d=(vxDelta(i,i+1,n)-vxDelta(i,i-1,n)) >= 0?1:-1;
        int dmin=vxDelta(i,i-d,n);

        int lmax=2;
        while(lmax<2*n&&vxDelta(i,i+lmax*d,n)>dmin) lmax <<= 1;

        int l=0;
        for(int t=lmax >> 1; t >= 1; t >>= 1){
            if(vxDelta(i,i+(l+t)*d,n)>dmin) l += t;
        }
        int j=i+l*d;

        int dnode=vxDelta(i,j,n);
        int s=0;
        int t=l;
        do {
            t=(t+1) >> 1;
            if(vxDelta(i,i+(s+t)*d,n)>dnode) s += t;
        } while(t>1);
        int gamma=i+s*d+min(d,0);

        bool leftLeaf =(min(i,j)==gamma);
        bool rightLeaf=(max(i,j)==gamma+1);
        uint left =leftLeaf ?uint(MAX_QUADS+gamma)    :uint(gamma);
        uint right=rightLeaf?uint(MAX_QUADS+gamma+1):uint(gamma+1);

        vxn.nodes[i].left=left;
        vxn.nodes[i].right=right;
        vxa.parent[left]=uint(i);
        vxa.parent[right]=uint(i);
        if(i==0) vxa.parent[0]=0xFFFFFFFFu;
    }

#endif

#ifdef PASS_REFIT

    layout(local_size_x=256) in;
    const ivec3 workGroups=ivec3(groupsQuads,1,1);

    void main(){
        uint k=gl_GlobalInvocationID.x;
        uint n=storeQDCount();
        if(k >= n) return;

        uint qid=vxa.sortedIds[k];
        storeQD q=vxq.quads[qid];
        vec3 lo=min(min(q.p0.xyz,q.p1.xyz),min(q.p2.xyz,q.p3.xyz))-vec3(1e-3);
        vec3 hi=max(max(q.p0.xyz,q.p1.xyz),max(q.p2.xyz,q.p3.xyz))+vec3(1e-3);

        uint leaf=uint(MAX_QUADS)+k;
        vxn.nodes[leaf].bmin=lo;
        vxn.nodes[leaf].left=qid;
        vxn.nodes[leaf].bmax=hi;
        vxn.nodes[leaf].right=0xFFFFFFFFu;

        if(n<2u) return;
        
        uint p=vxa.parent[leaf];
        while(true){
            memoryBarrierBuffer();
            uint old=atomicAdd(vxa.flags[p],1u);
            if(old==0u) return;
            memoryBarrierBuffer();

            uint l=vxn.nodes[p].left;
            uint r=vxn.nodes[p].right;
            vec3 lmin=vxn.nodes[l].bmin;
            vec3 lmax=vxn.nodes[l].bmax;
            vec3 rmin=vxn.nodes[r].bmin;
            vec3 rmax=vxn.nodes[r].bmax;
            vxn.nodes[p].bmin=min(lmin,rmin);
            vxn.nodes[p].bmax=max(lmax,rmax);

            if(p==0u) return;
            memoryBarrierBuffer();
            p=vxa.parent[p];
        }
    }

#endif