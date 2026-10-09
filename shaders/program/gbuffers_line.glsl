

#ifdef vsh

    uniform float viewWidth;
    uniform float viewHeight;

    out vec4 glcolor;

    const float LINE_WIDTH=2.;

    void main(){
        glcolor=gl_Color;

        vec2 res=vec2(viewWidth,viewHeight);
        vec4 p0=gl_ProjectionMatrix*(gl_ModelViewMatrix*gl_Vertex);
        vec4 p1=gl_ProjectionMatrix*(gl_ModelViewMatrix*vec4(gl_Vertex.xyz+gl_Normal,1.));
        vec3 ndc0=p0.xyz/p0.w;
        vec3 ndc1=p1.xyz/p1.w;

        vec2 dir=normalize((ndc1.xy-ndc0.xy)*res);
        vec2 offset=vec2(-dir.y,dir.x)*LINE_WIDTH/res;
        if(offset.x<0.) offset=-offset;

        vec3 ndc=(gl_VertexID%2==0)?ndc0+vec3(offset,0.):ndc0-vec3(offset,0.);
        gl_Position=vec4(ndc*p0.w,p0.w);
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