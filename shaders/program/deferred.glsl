

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
    #include "/lib/atmosphere/scattering.glsl"
    #include "/lib/lighting/gtao.glsl"

    in vec2 texcoord;

    /* RENDERTARGETS:0,4 */
    layout(location = 0) out vec4 color;
    layout(location = 1) out vec4 color4;

    vec3 worldSpacePosition(vec2 uv, float depth){
        vec4 clip=vec4(uv*2.-1.,depth*2.-1.,1.);
        vec4 viewSpace=gbufferProjectionInverse*clip;
        viewSpace/=viewSpace.w;
        vec4 worldSpace=gbufferModelViewInverse*viewSpace;
        return worldSpace.xyz;
    }

    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);
        vec4 albedo=texelFetch(colortex0,px,0);
        float depth=texelFetch(depthtex0,px,0).r;

        color=albedo;

        vec2 lm=texelFetch(colortex4,px,0).rg;
        float ao=1.;
        #ifdef GTAO_ENABLED
            ao=c(px,depth);
        #endif
        color4=vec4(lm,ao,1.);

        if(depth<1.) return;

        vec3 V=normalize(worldSpacePosition(texcoord,depth));
        vec3 S=normalize(sunDir);
        float alt=eyeAlt(cameraPosition.y);
        float disc=smoothstep(.9998,.99985,dot(V,S));

        vec3 sky;
        vec3 sun;
        if(alt>50.){
            vec3 O=vec3(0.,R+alt,0.);
            vec4 T;
            float g;
            vec4 L=calcInscattering(O,V,S,samplerTransmittance,T,g);
            if(g>0.){
                vec3 N=normalize(O+V*g);
                float c=dot(N,S);
                L+=T*sunIrr*vec4(.04,.06,.1,.11)*lutT(samplerTransmittance,c,0.)*max(c,0.);
            }
            sky=toRGB(L);
            sun=toRGB(sunIrr*T)*disc*(g<0.?1.:0.)*30.;
        }else{
            sky=skyRadiance(V);
            float sd=sin(skyDip(alt));
            sun=sunLight(S,alt)*disc*smoothstep(-sd-.02,-sd,V.y)*30.;
        }

        //color=vec4(pow(ACES(sky+sun),vec3(.4545455)),1.);
        color=vec4(sky+sun,1.);
    }

#endif