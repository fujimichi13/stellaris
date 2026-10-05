

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

    layout(r32ui) uniform uimage2D histX;
    layout(r32ui) uniform uimage2D histY;
    layout(r32f) uniform image2D warpX;
    layout(r32f) uniform image2D warpY;

    in vec2 texcoord;

    /* RENDERTARGETS:1 */
    layout(location = 0) out vec4 color;

    float loadX(int i){
        return (i<0||i>=256)?0.:float(imageLoad(histX,ivec2(i,0)).r);
    }
    float loadY(int i){
        return (i<0||i>=256)?0.:float(imageLoad(histY,ivec2(i,0)).r);
    }

    float blurX(int i){
        return loadX(i-2)+2.*loadX(i-1)+3.*loadX(i)+2.*loadX(i+1)+loadX(i+2);
    }
    float blurY(int i){
        return loadY(i-2)+2.*loadY(i-1)+3.*loadY(i)+2.*loadY(i+1)+loadY(i+2);
    }

    float cdfX(int bin){
        float total=0.;
        float prefix=0.;
        for(int i=0;i<256;i++){
            float w=blurX(i);
            total+=w;
            if(i<=bin) prefix+=w;
        }
        float uniformCdf=float(bin+1)/float(256);
        float measured=(total>0.)?prefix/total:uniformCdf;
        return mix(measured,uniformCdf,.3);
    }

    float cdfY(int bin){
        float total=0.;
        float prefix=0.;
        for(int i=0;i<256;i++){
            float w=blurY(i);
            total+=w;
            if(i<=bin) prefix+=w;
        }
        float uniformCdf=float(bin+1)/float(256);
        float measured=(total>0.0)?prefix/total:uniformCdf;
        return mix(measured,uniformCdf,.3);
    }

    void main(){
        ivec2 px=ivec2(gl_FragCoord.xy);

        if(px.y==0&&px.x<256){
            int bin=px.x;
            float identity=float(bin+1)/float(256);

            float oldX=imageLoad(warpX,ivec2(bin,0)).r;
            float oldY=imageLoad(warpY,ivec2(bin,0)).r;

            if(oldX<=0.) oldX=identity;
            if(oldY<=0.) oldY=identity;

            imageStore(warpX,ivec2(bin,0),vec4(mix(oldX,cdfX(bin),.05)));
            imageStore(warpY,ivec2(bin,0),vec4(mix(oldY,cdfY(bin),.05)));
        }

        color=vec4(0.0);
    }

#endif