

#ifdef vsh

    uniform mat4 gbufferModelViewInverse;

    in vec4 at_tangent;

    out vec4 glcolor;
    out vec2 texcoord;
    out vec2 vlightmap;
    out vec3 vNormal;
    out vec3 vTangent;
    out vec3 vBitangent;

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

        gl_Position=gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex;
    }

#endif

#ifdef fsh

    #include "/settings.glsl"
    #include "/lib/utility/uniforms.glsl"
    #include "/lib/surface/brdf.glsl"

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;
    in vec3 vTangent;
    in vec3 vBitangent;

    /* RENDERTARGETS: 0,2,3,4 */
    layout(location = 0) out vec4 color;
    layout(location = 1) out vec4 color2;
    layout(location = 2) out vec4 color3;
    layout(location = 3) out vec4 color4;

    void main(){
        vec4 albedo=texture(tex,texcoord)*glcolor;
        if(albedo.a<.1){
            discard;
        }

        vec4 spec=texture(specular,texcoord);
        vec4 nt=texture(normals,texcoord);

        float ao;
        vec3 N=decodeLabPBRNormal(nt,mat3(normalize(vTangent),normalize(vBitangent),normalize(vNormal)),ao);

        vec2 lm=saturate((vlightmap-.03125)/.9375);

        color=vec4(albedo.rgb,albedo.a);
        color2=spec;
        color3=vec4(N,ao);
        color4=vec4(lm,0.,1.);
    }

#endif