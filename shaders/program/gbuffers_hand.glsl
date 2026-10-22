

#include "/settings.glsl"
#include "/lib/utility/uniforms.glsl"

#ifdef vsh

    out vec4 glcolor;
    out vec2 texcoord;
    out vec2 vlightmap;
    out vec3 vNormal;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        vlightmap=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;
        vNormal=normalize(mat3(gbufferModelViewInverse)*(gl_NormalMatrix*gl_Normal));
        gl_Position=taaClip(gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex);
    }

#endif

#ifdef fsh

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;

    /* RENDERTARGETS: 0,2,3,4 */
    layout(location=0) out vec4 color;
    layout(location=1) out vec4 color2;
    layout(location=2) out vec4 color3;
    layout(location=3) out vec4 color4;

    void main(){
        vec4 albedo=texture(tex,texcoord,log2(RS))*glcolor;
        if(albedo.a<.1) discard;

        vec2 lm=clamp((vlightmap-.03125)/.9375,0.,1.);

        color=vec4(albedo.rgb,1.);
        color2=vec4(0.);
        color3=vec4(normalize(vNormal),1.);
        color4=vec4(lm,1.,1.);
    }

#endif
