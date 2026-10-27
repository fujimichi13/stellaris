
#include "/settings.glsl"
#include "/lib/utility/uniforms.glsl"

#ifdef vsh

    out vec4 glcolor;
    out vec2 texcoord;
    out vec2 vlightmap;
    out vec3 vNormal;
    out vec3 vWorldPos;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        vlightmap=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;
        vNormal=normalize(mat3(gbufferModelViewInverse)*(gl_NormalMatrix*gl_Normal));
        vWorldPos=(gbufferModelViewInverse*(gl_ModelViewMatrix*gl_Vertex)).xyz;
        gl_Position=taaClip(gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex);
    }

#endif

#ifdef fsh

    #include "/lib/surface/labpbr.glsl"

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;
    in vec3 vWorldPos;

    /* RENDERTARGETS: 13,14 */
    layout(location=0) out vec4 color;
    layout(location=1) out vec4 color1;

    void main(){
        vec4 albedo=texture(tex,texcoord,log2(RS))*glcolor;
        if(albedo.a<.05) discard;

        vec2 lm=clamp((vlightmap-.03125)/.9375,0.,1.);
        vec3 N=normalize(vNormal);
        if(dot(N,-vWorldPos)<0.) N=-N;
        color=vec4(N,-(4.+lm.y*.99));
        color1=albedo;
    }

#endif