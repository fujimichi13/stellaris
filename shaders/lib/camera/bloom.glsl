#ifndef BLOOM_GLSL
    #define BLOOM_GLSL a

    #include "/lib/utility/uniforms.glsl"

    vec3 softThreshold(vec3 c){
        float lum=max(max(c.r,max(c.g,c.b)),.0);
        float knee=1.*.5;
        float soft=clamp(lum-1.+knee,.0,2.*knee);
        soft=soft*soft/max(4.*knee,1e-5);
        float contrib=max(soft,lum-1.)/max(lum,1e-5);
        return c*contrib;
    }

    vec3 downsample13(sampler2D tex,vec2 uv,vec2 texel){
        vec3 a=texture(tex,uv+vec2(-2.,2.)*texel).rgb;
        vec3 b=texture(tex,uv+vec2( 0.,2.)*texel).rgb;
        vec3 c=texture(tex,uv+vec2( 2.,2.)*texel).rgb;
        vec3 d=texture(tex,uv+vec2(-2.,0.)*texel).rgb;
        vec3 e=texture(tex,uv).rgb;
        vec3 f=texture(tex,uv+vec2( 2.,0.)*texel).rgb;
        vec3 g=texture(tex,uv+vec2(-2.,-2.)*texel).rgb;
        vec3 h=texture(tex,uv+vec2( 0.,-2.)*texel).rgb;
        vec3 i=texture(tex,uv+vec2( 2.,-2.)*texel).rgb;
        vec3 j=texture(tex,uv+vec2(-1.,1.)*texel).rgb;
        vec3 k=texture(tex,uv+vec2( 1.,1.)*texel).rgb;
        vec3 l=texture(tex,uv+vec2(-1.,-1.)*texel).rgb;
        vec3 m=texture(tex,uv+vec2( 1.,-1.)*texel).rgb;

        vec3 groupA=(a+c+g+i)*.125;
        vec3 groupB=(b+d+f+h)*.125;
        vec3 groupC=(e+j+k+l+m)*.125;
        vec3 result=groupA*.25+groupB*.25+groupC*.5;

        float lum=dot(result,vec3(.2126,.7152,.0722));
        if (lum>8.) result*=8./lum;
        return result;
    }

    vec3 upsampleTent9(sampler2D tex,vec2 uv,vec2 texel,float radius){
        vec4 d=texel.xyxy*vec4(-1.,-1.,1.,1.)*radius;
        vec3 s=vec3(0.0);
        s+=texture(tex,uv+d.xy).rgb;
        s+=texture(tex,uv+vec2(0.,d.y)).rgb*2.;
        s+=texture(tex,uv+d.zy).rgb;
        s+=texture(tex,uv+vec2(d.x,0.)).rgb*2.;
        s+=texture(tex,uv).rgb*4.;
        s+=texture(tex,uv+vec2(d.z,0.)).rgb*2.;
        s+=texture(tex,uv+d.xw).rgb;
        s+=texture(tex,uv+vec2(0.,d.w)).rgb*2.;
        s+=texture(tex,uv+d.zw).rgb;
        return s/16.;
    }

    #ifdef PROGRAM_BLOOM_PREFILTER

        layout(local_size_x=8,local_size_y=8) in;

        const vec2 workGroupsRender=vec2(0.5,0.5);

        layout(r11f_g11f_b10f) uniform writeonly image2D bloom0;

        void main(){
            ivec2 px=ivec2(gl_GlobalInvocationID.xy);
            ivec2 size=imageSize(bloom0);
            if (any(greaterThanEqual(px,size))) return;

            vec2 uv=(vec2(px)+.5)/vec2(size);
            vec3 hdr=texture(colortex0,uv).rgb*.0625;
            if (any(isnan(hdr))) hdr=vec3(0.0);
            imageStore(bloom0,px,vec4(softThreshold(max(hdr,.0)),1.));
        }

    #endif

    #ifdef PROGRAM_BLOOM_DOWN2

        layout(local_size_x=8,local_size_y=8) in;

        const vec2 workGroupsRender=vec2(0.25,0.25);

        layout(r11f_g11f_b10f) uniform writeonly image2D bloom1;

        void main(){
            ivec2 px=ivec2(gl_GlobalInvocationID.xy);
            ivec2 size=imageSize(bloom1);
            if (any(greaterThanEqual(px,size))) return;

            vec2 uv=(vec2(px)+.5)/vec2(size);
            vec2 texel=1./vec2(textureSize(samplerBloom0,0));
            imageStore(bloom1,px,vec4(downsample13(samplerBloom0,uv,texel),1.));
        }

    #endif

    #ifdef PROGRAM_BLOOM_DOWN3

        layout(local_size_x=8,local_size_y=8) in;

        const vec2 workGroupsRender=vec2(0.125,0.125);

        layout(r11f_g11f_b10f) uniform writeonly image2D bloom2;

        void main(){
            ivec2 px=ivec2(gl_GlobalInvocationID.xy);
            ivec2 size=imageSize(bloom2);
            if (any(greaterThanEqual(px,size))) return;

            vec2 uv=(vec2(px)+.5)/vec2(size);
            vec2 texel=1./vec2(textureSize(samplerBloom1,0));
            imageStore(bloom2,px,vec4(downsample13(samplerBloom1,uv,texel),1.));
        }

    #endif

    #ifdef PROGRAM_BLOOM_DOWN4

        layout(local_size_x=8,local_size_y=8) in;

        const vec2 workGroupsRender=vec2(0.0625,0.0625);

        layout(r11f_g11f_b10f) uniform writeonly image2D bloom3;

        void main(){
            ivec2 px=ivec2(gl_GlobalInvocationID.xy);
            ivec2 size=imageSize(bloom3);
            if (any(greaterThanEqual(px,size))) return;

            vec2 uv=(vec2(px)+.5)/vec2(size);
            vec2 texel=1./vec2(textureSize(samplerBloom2,0));
            imageStore(bloom3,px,vec4(downsample13(samplerBloom2,uv,texel),1.));
        }

    #endif

    #ifdef PROGRAM_BLOOM_UP1

        layout(local_size_x=8,local_size_y=8) in;

        const vec2 workGroupsRender=vec2(0.125,0.125);

        layout(r11f_g11f_b10f) uniform image2D bloom2;

        void main(){
            ivec2 px=ivec2(gl_GlobalInvocationID.xy);
            ivec2 size=imageSize(bloom2);
            if (any(greaterThanEqual(px,size))) return;

            vec2 uv=(vec2(px)+.5)/vec2(size);
            vec2 texel=1./vec2(textureSize(samplerBloom3,0));
            vec3 up=upsampleTent9(samplerBloom3,uv,texel,1.);
            vec3 base=imageLoad(bloom2,px).rgb;
            imageStore(bloom2,px,vec4(base+up,1.));
        }

    #endif

    #ifdef PROGRAM_BLOOM_UP2

        layout(local_size_x=8,local_size_y=8) in;

        const vec2 workGroupsRender=vec2(0.25,0.25);

        layout(r11f_g11f_b10f) uniform image2D bloom1;

        void main(){
            ivec2 px=ivec2(gl_GlobalInvocationID.xy);
            ivec2 size=imageSize(bloom1);
            if (any(greaterThanEqual(px,size))) return;

            vec2 uv=(vec2(px)+.5)/vec2(size);
            vec2 texel=1./vec2(textureSize(samplerBloom2,0));
            vec3 up=upsampleTent9(samplerBloom2,uv,texel,1.);
            vec3 base=imageLoad(bloom1,px).rgb;
            imageStore(bloom1,px,vec4(base+up,1.));
        }

    #endif

#endif