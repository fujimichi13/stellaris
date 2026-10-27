

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

    #include "/lib/surface/labpbr.glsl"

    in vec4 glcolor;
    in vec2 texcoord;
    in vec2 vlightmap;
    in vec3 vNormal;

    /* RENDERTARGETS: 0,3 */
    layout(location=0) out vec4 color;
    layout(location=1) out uvec4 color1;

    void main(){
        vec4 albedo=texture(tex,texcoord,log2(RS))*glcolor;
        if(albedo.a<.1) discard;

        Material m=materialDefault(toLinear(albedo.rgb));
        vec4 spec=texture(specular,texcoord,log2(RS));
        spec.g=textureLod(specular,texcoord,0.).g;
        m=decodeLabPBR(spec,toLinear(albedo.rgb));
        m.id=MAT_HAND;

        vec2 lm=clamp((vlightmap-.03125)/.9375,0.,1.);

        color=vec4(albedo.rgb,1.);
        color1=gbPack(m,normalize(vNormal),lm,1.);
    }

#endif
