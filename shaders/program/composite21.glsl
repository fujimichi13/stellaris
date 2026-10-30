

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

    in vec2 texcoord;

    /* RENDERTARGETS:15 */
    layout(location=0) out vec4 color1;

    void main(){
        color1=vec4(max(texelFetch(colortex0,ivec2(gl_FragCoord.xy),0).rgb,0.),1.);
    }

#endif