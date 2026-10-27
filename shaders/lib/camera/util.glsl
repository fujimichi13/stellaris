#ifndef SVGF_UTILS
    #define SVGF_UTILS a

    #include "/lib/utility/encoding.glsl"

    layout(rgba32ui) uniform uimage2D moments;
    layout(rgba32ui) uniform uimage2D moments1;

    ivec2 T1(){
        return ivec2(0,int(RRES.y) >> 1);
    }

    uint packGeo(vec3 n,float len){
        n=(dot(n,n)>1e-12) ? n : vec3(0.,0.,1.);
        vec2 e=clamp(octEncode(n),0.,1.);
        uvec2 q=uvec2(e*4095.+.5);
        uint lc=uint(clamp(floor(log2(max(len,1.))*36.+.5),0.,255.));
        return q.x | (q.y << 12) | (lc << 24);
    }

    vec3 unPack(uint w){
        return octDecode(vec2(float(w & 4095u),float((w >> 12) & 4095u)) / 4095.);
    }

    float unpackLen(uint w){
        return exp2(float(w >> 24) / 36.);
    }

    vec4 geoFromWords(uint n,uint d){
        float dist=uintBitsToFloat(d);
        return (dist>0.) ? vec4(unPack(n),dist) : vec4(0.);
    }

    vec4 GeoHist(ivec2 q){
        uvec4 v=imageLoad(moments,q+T1());
        return geoFromWords(v.x,v.y);
    }

    vec4 GeoCur(ivec2 q){
        uvec4 v=imageLoad(moments,q+T1());
        return geoFromWords(v.z,v.w);
    }

    void ComGeo(ivec2 q){
        uvec4 g=imageLoad(moments,q+T1());
        imageStore(moments,q+T1(),uvec4(g.zw,g.zw));
    }

    void LoadHist(ivec2 q,out vec4 hc,out vec4 hm){
        uvec4 v=imageLoad(moments,q);
        hc=vec4(unpackHalf2x16(v.x),unpackHalf2x16(v.y));
        hm=vec4(uintBitsToFloat(v.z),uintBitsToFloat(v.w),0.,0.);
    }

    void StoreHist(ivec2 q,vec3 col,float len,vec2 mom){
        imageStore(moments,q,uvec4(packHalf2x16(col.rg),packHalf2x16(vec2(col.b,len)),floatBitsToUint(mom.x),floatBitsToUint(mom.y)));
    }

    void ClearHist(ivec2 q){
        imageStore(moments,q,uvec4(0u));
        uvec4 g=imageLoad(moments,q+T1());
        imageStore(moments,q+T1(),uvec4(0u,0u,g.zw));
    }

    void StoreCur(ivec2 q,vec4 colVar,vec2 mom,float len,vec3 N,float dist){
        imageStore(moments1,q,uvec4(packHalf2x16(colVar.rg),packHalf2x16(colVar.ba),floatBitsToUint(mom.x),floatBitsToUint(mom.y)));
        uvec4 g=imageLoad(moments,q+T1());
        imageStore(moments,q+T1(),uvec4(g.xy,packGeo(N,len),floatBitsToUint(dist)));
    }

    void StoreCurInvalid(ivec2 q){
        imageStore(moments1,q,uvec4(0u));
        uvec4 g=imageLoad(moments,q+T1());
        imageStore(moments,q+T1(),uvec4(g.xy,0u,0u));
    }

    void LoadCurN(ivec2 q,out vec2 mom,out float len){
        uvec4 a=imageLoad(moments1,q);
        mom=vec2(uintBitsToFloat(a.z),uintBitsToFloat(a.w));
        len=unpackLen(imageLoad(moments,q+T1()).z);
    }

    vec4 LoadSlot(ivec2 q,int s){
        uvec4 v=imageLoad(moments1,q);
        uvec2 u=(s==0) ? v.xy : v.zw;
        return vec4(unpackHalf2x16(u.x),unpackHalf2x16(u.y));
    }

    void StoreSlot(ivec2 q,int s,vec4 c){
        uvec4 v=imageLoad(moments1,q);
        uvec2 u=uvec2(packHalf2x16(c.rg),packHalf2x16(c.ba));
        imageStore(moments1,q,(s==0) ? uvec4(u,v.zw) : uvec4(v.xy,u));
    }

    vec3 OutputD(ivec2 q){
        return LoadSlot(q,1).rgb;
    }

#endif