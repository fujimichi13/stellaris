

#ifdef vsh

    in vec4 mc_Entity;

    uniform mat4 shadowModelViewInverse;

    out vec4 glcolor;
    out vec2 texcoord;

    out vec3 vxPos;
    out vec3 vxNormal;
    out float vxBlockId;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        vec3 snormal=normalize(gl_NormalMatrix*gl_Normal);

        vec4 viewPos=gl_ModelViewMatrix*gl_Vertex;
        vxPos=(shadowModelViewInverse*viewPos).xyz;
        vxNormal=normalize(mat3(shadowModelViewInverse)*snormal);
        vxBlockId=mc_Entity.x;

        gl_Position=gl_ProjectionMatrix*viewPos;
    }

#endif

#ifdef gsh

    #include "/settings.glsl"
    #include "/lib/utility/math.glsl"
    #include "/lib/voxel/voxel.glsl"

    layout(triangles) in;
    layout(triangle_strip,max_vertices=48) out;

    in vec4 glcolor[];
    in vec2 texcoord[];

    in vec3 vxPos[];
    in vec3 vxNormal[];
    in float vxBlockId[];

    out vec4 glcolor1;
    out vec2 texcoord1;

    uniform sampler2D samplerWarpX;
    uniform sampler2D samplerWarpY;
    uniform sampler2D tex;
    uniform vec3 cameraPosition;
    uniform int entityId;

    float rtwsmWarp1D(sampler2D tex,float u){
        if(u<=0.||u>=1.) return u;
        float t=u*float(256);
        int i=min(int(t),256-1);
        float f=t-float(i);
        float hi=texelFetch(tex,ivec2(i,0),0).r;
        if(hi<=0.) return u;
        float lo=(i==0)?0.:texelFetch(tex,ivec2(i-1,0),0).r;
        return mix(lo,hi,f);
    }

    vec2 rtwsmWarp(vec2 clipXY){
        vec2 uv=clipXY*.5+.5;
        vec2 w=vec2(rtwsmWarp1D(samplerWarpX,uv.x),rtwsmWarp1D(samplerWarpY,uv.y));
        return w*2.-1.;
    }

    void main(){
        do{
            vec3 a=vxPos[0];
            vec3 b=vxPos[1];
            vec3 c=vxPos[2];

            vec3 e0=a-b;
            vec3 e1=c-b;
            float l0=length(e0);
            float l1=length(e1);
            bool rect=abs(dot(e0,e1))<=0.05*l0*l1;

            bool oddTri=(gl_PrimitiveIDIn & 1)==1;
            if(rect&&oddTri) break;

            vec3 d=rect?(a+c-b):c;

            vec2 uv0=texcoord[0];
            vec2 uv1=texcoord[1];
            vec2 uv2=texcoord[2];
            vec2 uv3=rect?(uv0+uv2-uv1):uv2;

            vec3 n=cross(c-a,d-b);
            float nl=length(n);
            if(nl<1e-8) break;
            n /= nl;
            vec3 vn=vxNormal[0]+vxNormal[1]+vxNormal[2];
            if(dot(n,vn)<-0.25*length(vn)) n=-n;

            vec3 bmin=min(min(a,b),min(c,d));
            vec3 bmax=max(max(a,b),max(c,d));

            #ifdef PLAYER_CULL
            {
                const vec3 boxMin=vec3(-.75,-2.1,-.75);
                const vec3 boxMax=vec3( .75, .55, .75);
                bool inBox=!(any(lessThan(bmin,boxMin)) || any(greaterThan(bmax,boxMax)));
                if(inBox){
                    if(entityId==1) break;

                    vec3 g0=(a+cameraPosition)*16.;
                    vec3 g1=(b+cameraPosition)*16.;
                    vec3 g2=(c+cameraPosition)*16.;
                    vec3 g3=(d+cameraPosition)*16.;
                    vec3 off=max(max(abs(g0-round(g0)),abs(g1-round(g1))),max(abs(g2-round(g2)),abs(g3-round(g3))));
                    if(max(off.x,max(off.y,off.z))>.08) break;
                }
            }
            #endif

            uint idx=atomicAdd(vxh.quadCount,1u);
            if(idx >= uint(MAX_QUADS)){
                atomicAdd(vxh.overflow,1u);
                break;
            }

            vec4 tint=(glcolor[0]+glcolor[1]+glcolor[2]) / 3.;

            vec2 uvc=rect?(uv0+uv2)*.5:(uv0+uv1+uv2) / 3.;
            vec4 ts=textureLod(tex,uvc,2.);
            vec4 albedo=vec4(ts.rgb*tint.rgb,ts.a*tint.a);

            storeQD q;
            q.p0=vec4(a,uintBitsToFloat(packUnorm4x8(tint)));
            q.p1=vec4(b,uintBitsToFloat(uint(max(vxBlockId[0],0.))));
            q.p2=vec4(c,uintBitsToFloat(packUnorm4x8(albedo)));
            q.p3=vec4(d,0.);
            q.uv01=vec4(uv0,uv1);
            q.uv23=vec4(uv2,uv3);
            q.nrm=vec4(n,0.);

            for(int w=0; w<32; w++){
                uint pk=0u;
                for(int k=0; k<2; k++){
                    int i=w*2+k;
                    vec2 st=(vec2(i & 7,i >> 3)+.5) / 8.;
                    vec2 uvs=uv1+(uv0-uv1)*st.x+(uv2-uv1)*st.y;
                    vec3 tc=clamp(textureLod(tex,uvs,1.).rgb*tint.rgb,0.,1.);
                    uvec3 c5=uvec3(tc*vec3(31.,63.,31.)+.5);
                    pk |= ((c5.x << 11) | (c5.y << 5) | c5.z) << uint(16*k);
                }
                q.tx[w >> 2][w & 3]=pk;
            }

            vxq.quads[idx]=q;

            uint lightId=uint(max(vxBlockId[0],0.));
            if(lightId >= 10u&&lightId<=13u){
                uint li=atomicAdd(vxl.lightCount,1u);
                if(li<uint(16384)){
                    vec3 center=rect?(a+c)*.5:(a+b+c) / 3.;
                    int cell=lightCell(cellCoord(center));
                    if(cell >= 0){
                        vec3 lc;
                        if(lightId==11u)      lc=vec3(.25,.6,1.);
                        else if(lightId==12u) lc=vec3(1.,.12,.05);
                        else if(lightId==13u) lc=vec3(1.,.55,.2);
                        else {
                            vec3 g=pow(max(albedo.rgb,vec3(1e-3)),vec3(2.2));
                            g /= max(max(g.r,g.g),max(g.b,1e-3));
                            lc=clamp(mix(vec3(dot(g,vec3(.2126,.7152,.0722))),g,1.6),0.,1.);
                        }
                        vLight lt;
                        lt.a =vec4(b,uintBitsToFloat(packUnorm4x8(vec4(lc,1.))));
                        lt.e1=vec4(a-b,0.);
                        lt.e2=vec4(c-b,0.);
                        lt.n =vec4(n,0.);
                        vxl.lights[li]=lt;
                        uint slot=atomicAdd(vxl.cellCount[cell],1u);
                        if(slot<uint(16)) vxl.cellSlots[cell*16+int(slot)]=li;
                    }
                }
            }

            int ix0=encode(bmin.x),iy0=encode(bmin.y),iz0=encode(bmin.z);
            int ix1=encode(bmax.x),iy1=encode(bmax.y),iz1=encode(bmax.z);
            if(ix0<vxh.vMX) atomicMin(vxh.vMX,ix0);
            if(iy0<vxh.vMY) atomicMin(vxh.vMY,iy0);
            if(iz0<vxh.vMZ) atomicMin(vxh.vMZ,iz0);
            if(ix1>vxh.vMxX) atomicMax(vxh.vMxX,ix1);
            if(iy1>vxh.vMxY) atomicMax(vxh.vMxY,iy1);
            if(iz1>vxh.vMxZ) atomicMax(vxh.vMxZ,iz1);
        }while(false);

        for(int i=0;i<4;i++){
            for(int j=0;j<4-i;j++){
                for(int t=0;t<2;t++){
                    if(t==1&&i+j>2) break;
                    vec3 b[3];
                    if(t==0){
                        b[0]=vec3(4-i-j,i,j);
                        b[1]=vec3(3-i-j,i+1,j);
                        b[2]=vec3(3-i-j,i,j+1);
                    }else{
                        b[0]=vec3(3-i-j,i+1,j);
                        b[1]=vec3(2-i-j,i+1,j+1);
                        b[2]=vec3(3-i-j,i,j+1);
                    }
                    for(int k=0;k<3;k++){
                        vec3 w=b[k]/4.;
                        vec4 p=gl_in[0].gl_Position*w.x+gl_in[1].gl_Position*w.y+gl_in[2].gl_Position*w.z;
                        gl_Position=vec4(rtwsmWarp(p.xy),p.z,p.w);
                        glcolor1=glcolor[0]*w.x+glcolor[1]*w.y+glcolor[2]*w.z;
                        texcoord1=texcoord[0]*w.x+texcoord[1]*w.y+texcoord[2]*w.z;
                        EmitVertex();
                    }
                    EndPrimitive();
                }
            }
        }
    }

#endif

#ifdef fsh

    uniform sampler2D tex;

    in vec4 glcolor1;
    in vec2 texcoord1;

    /* RENDERTARGETS: 0 */
    layout(location=0) out vec4 color;

    const int shadowMapResolution=2048;
    const float shadowDistance=192.0;

    void main(){
        vec4 albedo=texture(tex,texcoord1)*glcolor1;

        if(albedo.a<.1){
            discard;
        }

        color=vec4(albedo.rgb,albedo.a);
    }

#endif