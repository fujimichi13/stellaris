

#include "/settings.glsl"
#include "/lib/utility/uniforms.glsl"

#ifdef vsh

    out vec4 glcolor;

    void main(){
        glcolor=gl_Color;
        gl_Position=taaClip(gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex);
    }

#endif

#ifdef fsh

    in vec4 glcolor;

    /* RENDERTARGETS: 0 */
    layout(location=0) out vec4 color;

    void main(){
        color=vec4(1.,1.,1.,1.);
    }

#endif