#ifndef VOXEL_GLSL
    #define VOXEL_GLSL a

    #include "/lib/utility/math.glsl"

    #if MAX_QUADS==65536
        #define groupsQuads 256
    #elif MAX_QUADS==131072
        #define groupsQuads 512
    #elif MAX_QUADS==262144
        #define groupsQuads 1024
    #else
        #define groupsQuads 2048
    #endif

    int encode(float f){
        int i=floatBitsToInt(f);
        return i ^ ((i >> 31) & 0x7FFFFFFF);
    }
    float decode(int i){
        return intBitsToFloat(i ^ ((i >> 31) & 0x7FFFFFFF));
    }

    struct storeQD {
        vec4 p0;
        vec4 p1;
        vec4 p2;
        vec4 p3;
        vec4 uv01;
        vec4 uv23;
        vec4 nrm;
        uvec4 tx[8];
    };

    struct node {
        vec3 bmin;
        uint left;
        vec3 bmax;
        uint right;
    };

    struct hit {
        float t;
        uint quad;
        vec3 normal;
        vec2 uv;
        vec2 st;
    };

    layout(std430,binding=0) coherent buffer header {
        uint quadCount; 
        uint overflow;
        uint reserved0;
        uint reserved1;
        int vMX;
        int vMY;
        int vMZ;
        int vMPad;
        int vMxX;
        int vMxY;
        int vMxZ;
        int vMxPad;
        uint reserved2[4];
        uint bucketCount[262144];
        uint bucketCursor[262144];
    } vxh;

    struct vLight {
        vec4 a;
        vec4 e1;
        vec4 e2;
        vec4 n;
    };

    vec3 vM(){
        return vec3(decode(vxh.vMX),decode(vxh.vMY),decode(vxh.vMZ));
    }
    vec3 vMx(){
        return vec3(decode(vxh.vMxX),decode(vxh.vMxY),decode(vxh.vMxZ));
    }

    layout(std430,binding=4) coherent buffer vLightB {
        uint lightCount;
        uint lightPad0;
        uint lightPad1;
        uint lightPad2;
        uint cellCount[16384];
        uint cellSlots[16384*16];
        vLight lights[16384];
    } vxl;

    layout(std430,binding=1) buffer storeQDB {
        storeQD quads[];
    } vxq;

    layout(std430,binding=2) coherent buffer nodeB {
        node nodes[];
    } vxn;


    layout(std430,binding=5) buffer playerSkinB {
        uint texels[64*64];
    } vxp;

    layout(std430,binding=3) buffer auxB {
        uint sortedKeys[MAX_QUADS];
        uint sortedIds[MAX_QUADS];
        uint flags[MAX_QUADS];
        uint parent[2*MAX_QUADS];
    } vxa;

    vec4 playerSkin(vec2 uv){
        ivec2 t=clamp(ivec2(floor(uv*float(64))),ivec2(0),ivec2(64-1));
        return unpackUnorm4x8(vxp.texels[t.y*64+t.x]);
    }

    vec2 quadUV(in storeQD q,int tri,vec2 bc){
        if(tri==0) return q.uv01.xy*(1.-bc.x-bc.y)+q.uv01.zw*bc.x+q.uv23.xy*bc.y;
        return q.uv01.xy*(1.-bc.x-bc.y)+q.uv23.xy*bc.x+q.uv23.zw*bc.y;
    }

    ivec3 cellCoord(vec3 p){
        return ivec3(floor(p / 8.))+ivec3(16,8,16);
    }

    int lightCell(ivec3 c){
        if(any(lessThan(c,ivec3(0))) || any(greaterThanEqual(c,ivec3(32,16,32)))) return -1;
        return (c.y*32+c.z)*32+c.x;
    }

    uint storeQDCount(){
        return min(vxh.quadCount,uint(MAX_QUADS));
    }

    uint expandBits(uint v){
        v=(v*0x00010001u) & 0xFF0000FFu;
        v=(v*0x00000101u) & 0x0F00F00Fu;
        v=(v*0x00000011u) & 0xC30C30C3u;
        v=(v*0x00000005u) & 0x49249249u;
        return v;
    }

    uint morton(vec3 p,vec3 bmin,vec3 bmax){
        vec3 t=clamp((p-bmin) / max(bmax-bmin,vec3(1e-3)),0.,1.);
        uvec3 q=min(uvec3(t*1024.),uvec3(1023u));
        return (expandBits(q.x) << 2) | (expandBits(q.y) << 1) | expandBits(q.z);
    }

    vec3 storeQDCentroid(in storeQD q){
        return (q.p0.xyz+q.p1.xyz+q.p2.xyz+q.p3.xyz)*.25;
    }

    float testAABB(vec3 bmin,vec3 bmax,vec3 ro,vec3 invD,float tMax){
        vec3 t0=(bmin-ro)*invD;
        vec3 t1=(bmax-ro)*invD;
        vec3 tn=min(t0,t1);
        vec3 tf=max(t0,t1);
        float tNear=max(max(tn.x,tn.y),max(tn.z,0.));
        float tFar =min(min(tf.x,tf.y),min(tf.z,tMax));
        return (tNear<=tFar)?tNear:1e30;
    }
    
    float vtri(vec3 a,vec3 b,vec3 c,vec3 ro,vec3 rd,out vec2 bary){
        vec3 e1=b-a;
        vec3 e2=c-a;
        vec3 p=cross(rd,e2);
        float det=dot(e1,p);
        bary=vec2(0.);
        if(abs(det)<1e-9) return -1.;
        float inv=1. / det;
        vec3 s=ro-a;
        float u=dot(s,p)*inv;
        if(u<0. || u>1.) return -1.;
        vec3 qv=cross(s,e1);
        float v=dot(rd,qv)*inv;
        if(v<0. || u+v>1.) return -1.;
        bary=vec2(u,v);
        return dot(e2,qv)*inv;
    }

    bool intersectQuad(uint id,vec3 ro,vec3 rd,inout float tBest,inout hit hit){
        storeQD q=vxq.quads[id];
        vec3 p0=q.p0.xyz;
        vec3 p1=q.p1.xyz;
        vec3 p2=q.p2.xyz;
        vec3 p3=q.p3.xyz;
        bool found=false;
        vec2 bc;

        float t=vtri(p0,p1,p2,ro,rd,bc);
        if(t>1e-4&&t<tBest){
            tBest=t;
            hit.t=t; hit.quad=id; hit.normal=q.nrm.xyz;
            hit.uv=q.uv01.xy*(1.-bc.x-bc.y)+q.uv01.zw*bc.x+q.uv23.xy*bc.y;
            hit.st=vec2(1.-bc.x-bc.y,bc.y);
            found=true;
        }
        t=vtri(p0,p2,p3,ro,rd,bc);
        if(t>1e-4&&t<tBest){
            tBest=t;
            hit.t=t; hit.quad=id; hit.normal=q.nrm.xyz;
            hit.uv=q.uv01.xy*(1.-bc.x-bc.y)+q.uv23.xy*bc.x+q.uv23.zw*bc.y;
            hit.st=vec2(1.-bc.x,bc.x+bc.y);
            found=true;
        }
        return found;
    }


    bool trace(vec3 ro,vec3 rd,float tMax,out hit hit){
        hit.t=tMax;
        hit.quad=0xFFFFFFFFu;
        hit.normal=vec3(0.);
        hit.uv=vec2(0.);
        hit.st=vec2(0.);

        uint n=storeQDCount();
        if(n==0u) return false;

        rd=mix(rd,vec3(1e-6),lessThan(abs(rd),vec3(1e-6)));
        vec3 invD=1. / rd;
        float tBest=tMax;
        bool any=false;

        if(n==1u){
            node leaf=vxn.nodes[MAX_QUADS];
            if(testAABB(leaf.bmin,leaf.bmax,ro,invD,tBest)<1e29)
                any=intersectQuad(leaf.left,ro,rd,tBest,hit);
            return any;
        }

        uint stack[64];
        int sp=0;

        node root=vxn.nodes[0];
        if(testAABB(root.bmin,root.bmax,ro,invD,tBest)>1e29) return false;
        stack[sp++]=0u;

        while(sp>0){
            uint cur=stack[--sp];
            node nd=vxn.nodes[cur];

            uint ci[2];
            float ct[2];
            ci[0]=nd.left;
            ci[1]=nd.right;
            ct[0]=1e30;
            ct[1]=1e30;

            for(int k=0; k<2; k++){
                node ch=vxn.nodes[ci[k]];
                float tc=testAABB(ch.bmin,ch.bmax,ro,invD,tBest);
                if(tc>1e29) continue;
                if(ci[k] >= uint(MAX_QUADS)){
                    if(intersectQuad(ch.left,ro,rd,tBest,hit)) any=true;
                } else {
                    ct[k]=tc;
                }
            }

            bool nearFirst=ct[0]<=ct[1];
            uint nearC=nearFirst?ci[0]:ci[1];
            uint farC =nearFirst?ci[1]:ci[0];
            float nearT=nearFirst?ct[0]:ct[1];
            float farT =nearFirst?ct[1]:ct[0];
            if(farT<1e29&&sp<63) stack[sp++]=farC;
            if(nearT<1e29&&sp<63) stack[sp++]=nearC;
        }
        return any;
    }

    bool storeQDOccludes(uint id,vec3 ro,vec3 rd,float tMax){
        storeQD q=vxq.quads[id];
        vec2 bc;
        int tri=0;
        float t=vtri(q.p0.xyz,q.p1.xyz,q.p2.xyz,ro,rd,bc);
        bool h=(t>1e-4&&t<tMax);
        if(!h){
            t=vtri(q.p0.xyz,q.p2.xyz,q.p3.xyz,ro,rd,bc);
            h=(t>1e-4&&t<tMax);
            tri=1;
        }
        if(!h) return false;
        uint bid=floatBitsToUint(q.p1.w);
        if(bid >= 1u&&bid<=3u) return false;
        #ifdef VOXELIZE_PLAYER
        if(bid==20u) return playerSkin(quadUV(q,tri,bc)).a>.5;
        #endif
        return unpackUnorm4x8(floatBitsToUint(q.p2.w)).a>0.5;
    }

    bool traceAny(vec3 ro,vec3 rd,float tMax){
        uint n=storeQDCount();
        if(n==0u) return false;

        rd=mix(rd,vec3(1e-6),lessThan(abs(rd),vec3(1e-6)));
        vec3 invD=1. / rd;

        if(n==1u){
            node leaf=vxn.nodes[MAX_QUADS];
            if(testAABB(leaf.bmin,leaf.bmax,ro,invD,tMax)>1e29) return false;
            return storeQDOccludes(leaf.left,ro,rd,tMax);
        }

        uint stack[64];
        int sp=0;

        node root=vxn.nodes[0];
        if(testAABB(root.bmin,root.bmax,ro,invD,tMax)>1e29) return false;
        stack[sp++]=0u;

        while(sp>0){
            uint cur=stack[--sp];
            node nd=vxn.nodes[cur];
            for(int k=0; k<2; k++){
                uint ci=(k==0)?nd.left:nd.right;
                node ch=vxn.nodes[ci];
                if(testAABB(ch.bmin,ch.bmax,ro,invD,tMax)>1e29) continue;
                if(ci >= uint(MAX_QUADS)){
                    if(storeQDOccludes(ch.left,ro,rd,tMax)) return true;
                } else if(sp<63){
                    stack[sp++]=ci;
                }
            }
        }
        return false;
    }

    vec3 gtint(vec3 gammaRgb){
        vec3 c=pow(gammaRgb,vec3(2.2));
        float m=max(max(c.r,c.g),c.b);
        if(m<.02) return vec3(1.);
        return sqrt(mix(vec3(1.),c / m,.9));
    }

    bool storeQDTransmit(uint id,vec3 ro,vec3 rd,float tMax,inout vec3 T){
        storeQD q=vxq.quads[id];
        vec2 bc;
        int tri=0;
        float t=vtri(q.p0.xyz,q.p1.xyz,q.p2.xyz,ro,rd,bc);
        bool h=(t>1e-4&&t<tMax);
        if(!h){
            t=vtri(q.p0.xyz,q.p2.xyz,q.p3.xyz,ro,rd,bc);
            h=(t>1e-4&&t<tMax);
            tri=1;
        }
        if(!h) return true;
        uint bid=floatBitsToUint(q.p1.w);
        #ifdef VOXELIZE_PLAYER
        if(bid==20u) return playerSkin(quadUV(q,tri,bc)).a<=.5;
        #endif
        vec4 a=unpackUnorm4x8(floatBitsToUint(q.p2.w));
        if(bid==1u) return true;
        if(bid==2u || bid==3u){
            T *= gtint(a.rgb);
            return true;
        }
        return a.a<=.5;
    }

    vec3 traceTrans(vec3 ro,vec3 rd,float tMax){
        vec3 T=vec3(1.);
        uint n=storeQDCount();
        if(n==0u) return T;

        rd=mix(rd,vec3(1e-6),lessThan(abs(rd),vec3(1e-6)));
        vec3 invD=1. / rd;

        if(n==1u){
            node leaf=vxn.nodes[MAX_QUADS];
            if(testAABB(leaf.bmin,leaf.bmax,ro,invD,tMax)>1e29) return T;
            return storeQDTransmit(leaf.left,ro,rd,tMax,T)?T:vec3(0.);
        }

        uint stack[64];
        int sp=0;

        node root=vxn.nodes[0];
        if(testAABB(root.bmin,root.bmax,ro,invD,tMax)>1e29) return T;
        stack[sp++]=0u;

        while(sp>0){
            uint cur=stack[--sp];
            node nd=vxn.nodes[cur];
            for(int k=0; k<2; k++){
                uint ci=(k==0)?nd.left:nd.right;
                node ch=vxn.nodes[ci];
                if(testAABB(ch.bmin,ch.bmax,ro,invD,tMax)>1e29) continue;
                if(ci >= uint(MAX_QUADS)){
                    if(!storeQDTransmit(ch.left,ro,rd,tMax,T)) return vec3(0.);
                } else if(sp<63){
                    stack[sp++]=ci;
                }
            }
            if(max(T.r,max(T.g,T.b))<.01) return vec3(0.);
        }
        return T;
    }

    bool closest(vec3 ro,vec3 rd,float tMax,out hit h,out vec4 alb,out uint bid,out float tHit,out vec3 tint){
        tHit=0.;
        tint=vec3(1.);
        alb=vec4(0.);
        bid=0u;
        for(int k=0; k<4; k++){
            if(!trace(ro,rd,tMax-tHit,h)) return false;
            storeQD q=vxq.quads[h.quad];
            bid=floatBitsToUint(q.p1.w);
            alb=unpackUnorm4x8(floatBitsToUint(q.p2.w));
            bool skip=(bid >= 1u&&bid<=3u) || (rand()>alb.a);
            #ifdef VOXELIZE_PLAYER
                if(bid==20u){
                    alb=playerSkin(h.uv);
                    skip=alb.a<.5;
                }
            #endif
            if(!skip){
                tHit += h.t;
                return true;
            }
            if(bid==2u || bid==3u) tint *= gtint(alb.rgb);
            float adv=h.t+.003;
            ro += rd*adv;
            tHit += adv;
        }
        return false;
    }

#endif