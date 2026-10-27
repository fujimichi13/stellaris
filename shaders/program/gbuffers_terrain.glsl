

#include "/settings.glsl"
#include "/lib/utility/math.glsl"
#include "/lib/utility/random.glsl"
#include "/lib/utility/uniforms.glsl"

#ifdef vsh

    in vec4 at_tangent;

    out vec4 glcolor;
    out vec2 texcoord;
    out vec2 vlightmap;
    out vec3 vNormal;
    out vec3 vTangent;
    out vec3 vBitangent;
    out vec3 vWorldPos;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        vlightmap=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;

        mat3 toWorld=mat3(gbufferModelViewInverse);
        vec3 N=normalize(toWorld*(gl_NormalMatrix*gl_Normal));
        vec3 T=normalize(toWorld*(gl_NormalMatrix*at_tangent.xyz));
        vec3 B=normalize(cross(T,N)*at_tangent.w);
        vNormal=N;
        vTangent=T;
        vBitangent=B;
        vWorldPos=(gbufferModelViewInverse*(gl_ModelViewMatrix*gl_Vertex)).xyz+cameraPosition;

        gl_Position=taaClip(gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex);
    }

#endif

#ifdef fsh

    #include "/lib/surface/labpbr.glsl"

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;
    in vec3 vTangent;
    in vec3 vBitangent;
    in vec3 vWorldPos;

    /* RENDERTARGETS: 0,3 */
    layout(location=0) out vec4 color;
    layout(location=1) out uvec4 color1;


    float valuen(vec2 p){
        vec2 f=fract(p);
        f=f*f*(3.-2.*f);
        return mix(mix(hash12(floor(p)),hash12(floor(p)+vec2(1.,0.)),f.x),mix(hash12(floor(p)+vec2(0.,1.)),hash12(floor(p)+vec2(1.,1.)),f.x),f.y);
    }

    float puddlenoise(vec2 p){
        float n=valuen(p*.22)*.55;
        n+=valuen(p*.61+17.3)*.30;
        n+=valuen(p*1.7+41.1)*.15;
        return n;
    }

    vec2 ripple(vec2 wp,float tileSize,float fps,float seed){
        ivec2 sz=textureSize(rippleTex,0);
        bool vert=sz.y>sz.x;
        int fs=vert?sz.x:sz.y;
        int frames=max((vert?sz.y:sz.x)/fs,1);

        vec2 uv=wp/tileSize+seed;
        vec2 id=floor(uv);
        int fr=(int(floor(frameTimeCounter*fps))+int(hash12(id+seed*13.)*float(frames)))%frames;

        vec2 p=fract(uv)*float(fs)-.5;
        ivec2 i0=ivec2(floor(p));
        vec2 f=fract(p);
        ivec2 i1=i0+1;
        if(i0.x<0) i0.x+=fs;
        if(i0.y<0) i0.y+=fs;
        if(i1.x>=fs) i1.x-=fs;
        if(i1.y>=fs) i1.y-=fs;

        ivec2 off=vert?ivec2(0,fr*fs):ivec2(fr*fs,0);
        vec2 a=texelFetch(rippleTex,off+i0,0).rg;
        vec2 b=texelFetch(rippleTex,off+ivec2(i1.x,i0.y),0).rg;
        vec2 c=texelFetch(rippleTex,off+ivec2(i0.x,i1.y),0).rg;
        vec2 d=texelFetch(rippleTex,off+i1,0).rg;
        vec2 n=mix(mix(a,b,f.x),mix(c,d,f.x),f.y)*2.-1.;
        //#ifdef FLIP_Y
        //    n.y=-n.y;
        //#endif
        return n;
    }

    void rainPuddles(vec3 worldPos,vec3 Ng,vec2 lm,inout vec3 albedo,inout Material m,inout vec3 N){
        float rain=saturate(cloudRain);
        float sky=smoothstep(.75,.95,lm.y);
        if(rain<.001||sky<.001||m.metallic>.5) return;

        float por=m.porosity;

        float soak=saturate((rain-por*.6)/(1.-por*.6));
        float cover=soak*(1.-por*.8);

        float up=smoothstep(.3,.9,Ng.y);
        float flat_=smoothstep(.9,.99,Ng.y);

        float n=puddlenoise(worldPos.xz);
        float thr=mix(.72,.42,cover);
        float puddle=saturate(smoothstep(thr,thr+.1,n)*flat_*sky*cover*PUDDLES_AMOUNT);

        float film=rain*sky*mix(.5,1.,up);
        float wetAmt=saturate(max(film,puddle));

        float darken=.5*wetAmt*mix(.5,1.6,por)*(1.+.6*puddle);
        albedo=pow(albedo,vec3(1.+darken));

        float smoothTarget=mix(mix(.7,.42,por),.97,puddle);
        m.smoothness=mix(m.smoothness,max(m.smoothness,smoothTarget),wetAmt);
        m.F0=max(m.F0,vec3(.04*saturate(wetAmt*2.)));
        materialFinalize(m);

        N=normalize(mix(N,Ng,saturate(wetAmt*.35+puddle*.65)));

        float fade=1.-smoothstep(20.,56.,length(worldPos-cameraPosition));
        float rm=saturate(puddle+.3*film*flat_*(1.-por))*saturate(rainStrength*1.5)*fade*1.;
        if(rm>.001){
            vec2 r=ripple(worldPos.xz,0.6,60.,0.)*.7;
            r+=ripple(worldPos.xz,0.6*1.37,60.*.83,5.7)*.7;
            N=normalize(N+vec3(r.x,0.,r.y)*rm);
        }
    }

    void main(){
        vec4 albedo=texture(tex,texcoord,log2(RS))*glcolor;
        if(albedo.a<.1){
            discard;
        }

        vec4 spec=texture(specular,texcoord,log2(RS));
        spec.g=textureLod(specular,texcoord,0.).g;
        vec4 nt=texture(normals,texcoord,log2(RS));

        float ao;
        vec3 N=decodeLabPBRNormal(nt,mat3(normalize(vTangent),normalize(vBitangent),normalize(vNormal)),ao);

        vec2 lm=saturate((vlightmap-.03125)/.9375);

        Material m=decodeLabPBR(spec,toLinear(albedo.rgb));
        m.ao=ao;
        m.id=MAT_TERRAIN;

        #ifdef PUDDLES_ENABLED
            rainPuddles(vWorldPos,normalize(vNormal),lm,albedo.rgb,m,N);
        #endif

        color=vec4(albedo.rgb,albedo.a);
        color1=gbPack(m,N,lm,0.);
    }

#endif
