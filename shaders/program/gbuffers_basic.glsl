

#ifdef vsh

    out vec4 glcolor;

    void main(){
        glcolor=gl_Color;
        gl_Position=gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex;
    }

#endif

#ifdef fsh

    #include "/settings.glsl"
    #include "/lib/utility/uniforms.glsl"

    in vec4 glcolor;

    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 color;

    void main(){
        color=glcolor;
    }

#endif