

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

    /*
    const int colortex0Format = RGBA16F;
    const int colortex9Format = RGBA16F;
    const int colortex10Format = RGBA16F;
    const int colortex11Format = RGBA16F;
    const int colortex12Format = RGBA16F;
    */

    #include "/lib/camera/bloom.glsl"

    in vec2 texcoord;

    layout(location = 0) out vec4 color;

    vec3 AgxDefaultContrastApprox(vec3 x){
        return (((((15.5*x-40.14)*x+31.96)*x-6.868)*x+.4298)*x+.1191)*x-.00232;
    }

    vec3 AgX(vec3 color){
        color=max(color,0.)*.0625;
        color*=2.3;

        color*=mat3(0.99999976,-1.26657e-7,-1.29064e-9,1.67316e-8,0.99999976,-5.32026e-9,-0.00725587,6.47740e-9,1.00725580);
        color*=mat3(0.842479062253094,0.0784335999999992,0.0792237451477643,0.0423282422610123,0.878468636469772,0.0791661274605434,0.0423756549057051,0.0784336,0.879142973793104);

        const float hev=14.*.5;
        const float middle_grey=.18;
        color=clamp(log2(max(color,1e-6)/middle_grey),-hev,hev);
        color=(color+hev)/14.;

        color=AgxDefaultContrastApprox(color);

        color*=mat3(1.19687900512017,-0.0980208811401368,-0.0990297440797205,-0.0528968517574562,1.15190312990417,-0.0989611768448433,-0.0529716355144438,-0.0980434501171241,1.15107367264116);

        return clamp(color,0.,1.);
    }

    void main(){
        vec4 c=texture(colortex0,texcoord);

        vec3 bloom=upsampleTent9(colortex10,texcoord,1./vec2(textureSize(colortex10,0)),1.);
        vec3 hdr=c.rgb+bloom*(BLOOM_STRENGTH/.0625);

        color=vec4(AgX(hdr),c.a);
    }

#endif