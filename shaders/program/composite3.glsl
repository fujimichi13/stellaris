

#ifdef vsh

    out vec2 texcoord;

    void main(){
        gl_Position=ftransform();
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    }

#endif

#ifdef fsh

    #include "/settings.glsl"
    #include "/lib/utility/uniforms.glsl"
    #include "/lib/surface/brdf.glsl"

    in vec2 texcoord;

    /* RENDERTARGETS:8 */
    layout(location = 0) out vec4 color;

    #define RAYTRACE_STEPS 64
    #define RAYTRACE_REFINEMENT 6

    vec2 bluenoise(vec2 fragCoord){
        vec2 b=texelFetch(noisetex,ivec2(fragCoord)&127,0).rg;
        #ifdef TAA_ENABLED
            b=fract(b+float(frameCounter&63)*vec2(.7548777,.5698403));
        #endif
        return b;
    }

    vec3 viewSpacePosition(vec2 uv, float depth){
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return v.xyz/v.w;
    }

    float viewDepth(float d){
        return -gbufferProjection[3][2]/(d*2.-1.+gbufferProjection[2][2]);
    }

    #include "/lib/surface/ssr.glsl"

    void main(){
        color=vec4(0.);

        ivec2 px=ivec2(gl_FragCoord.xy);
        float depth=texelFetch(depthtex0,px,0).r;
        if(depth>=1.) return;

        vec4 nd=texelFetch(colortex3,px,0);
        vec4 wn=texelFetch(colortex13,px,0);

        vec3 P=viewSpacePosition(texcoord,depth);
        vec3 V=-normalize(mat3(gbufferModelViewInverse)*P);

        if(abs(wn.w)<.5&&dot(nd.xyz,nd.xyz)>=.25){
            vec3 N=normalize(nd.xyz);
            Material m=decodeLabPBR(texelFetch(colortex2,px,0),vec3(0.));
            if(m.roughness>=.4) return;

            vec3 Rm=reflect(-V,N);
            vec2 bn=bluenoise(gl_FragCoord.xy);
            vec2 bn2=bluenoise(gl_FragCoord.xy+vec2(37.,17.));
            float a=m.roughness*m.roughness;
            float ph=bn.x*6.2831853;
            float cz=bn.y*2.-1.;
            vec3 j=vec3(sqrt(1.-cz*cz)*vec2(cos(ph),sin(ph)),cz);
            vec3 Rw=normalize(Rm+j*a*2.);
            if(dot(Rw,N)<.02) Rw=Rm;

            vec3 D=normalize(mat3(gbufferModelView)*Rw);
            vec3 Nv=normalize(mat3(gbufferModelView)*N);
            color=screenSpaceReflection(P+Nv*(.02-P.z*.004),D,Rw,bn2.x);
            return;
        }

        if(wn.w>.5&&isEyeInWater==0){
            vec3 N=normalize(wn.xyz);
            vec3 R=reflect(-V,N);
            R.y=abs(R.y);
            vec3 D=normalize(mat3(gbufferModelView)*R);
            vec3 Nv=normalize(mat3(gbufferModelView)*N);
            color=screenSpaceReflection(P+Nv*(.02-P.z*.004),D,R,bluenoise(gl_FragCoord.xy).x);
            return;
        }

        if(wn.w<-.5){
            vec3 N=normalize(wn.xyz);
            vec3 R=reflect(-V,N);
            vec3 D=normalize(mat3(gbufferModelView)*R);
            vec3 Nv=normalize(mat3(gbufferModelView)*N);
            color=screenSpaceReflection(P+Nv*(.02-P.z*.004),D,R,bluenoise(gl_FragCoord.xy).x);
        }
    }

#endif
