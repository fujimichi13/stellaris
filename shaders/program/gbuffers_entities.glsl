

#ifdef vsh

    out vec4 glcolor;
    out vec2 texcoord;

    void main(){
        glcolor=gl_Color;
        texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
        gl_Position=gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex;
    }

#endif

#ifdef fsh

    #include "/settings.glsl"
    #include "/lib/utility/uniforms.glsl"

    in vec4 glcolor;
    in vec2 texcoord;

    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 color;

    void main(){
        vec4 albedo=texture(tex,texcoord)*glcolor;
        if(albedo.a<.01) discard;
        color=albedo;
    }

#endif