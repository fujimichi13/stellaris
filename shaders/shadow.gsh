#version 430 compatibility

layout(triangles) in;
layout(triangle_strip, max_vertices = 48) out;

in vec4 glcolor[];
in vec2 texcoord[];

in vec3 snormal[];
out vec3 snormal1;

out vec4 glcolor1;
out vec2 texcoord1;

uniform sampler2D samplerWarpX;
uniform sampler2D samplerWarpY;

float rtwsmWarp1D(sampler2D tex, float u){
    if(u<=0.||u>=1.) return u;
    float t=u*float(256);
    int i=min(int(t),256-1);
    float f=t-float(i);
    float hi=texelFetch(tex,ivec2(i,0),0).r;
    if(hi<=0.) return u;
    float lo=(i==0)?0.:texelFetch(tex,ivec2(i-1,0),0).r;
    return mix(lo,hi,f);
}

vec2 rtwsmWarp(vec2 clipXY){
    vec2 uv=clipXY*.5+.5;
    vec2 w=vec2(rtwsmWarp1D(samplerWarpX,uv.x), rtwsmWarp1D(samplerWarpY,uv.y));
    return w*2.-1.;
}

void main(){
    for(int i=0;i<4;i++){
        for(int j=0;j<4-i;j++){
            for(int t=0;t<2;t++){
                if(t==1&&i+j>2) break;
                vec3 b[3];
                if(t==0){
                    b[0]=vec3(4-i-j,i,j);
                    b[1]=vec3(3-i-j,i+1,j);
                    b[2]=vec3(3-i-j,i,j+1);
                }else{
                    b[0]=vec3(3-i-j,i+1,j);
                    b[1]=vec3(2-i-j,i+1,j+1);
                    b[2]=vec3(3-i-j,i,j+1);
                }
                for(int k=0;k<3;k++){
                    vec3 w=b[k]/4.;
                    vec4 p=gl_in[0].gl_Position*w.x+gl_in[1].gl_Position*w.y+gl_in[2].gl_Position*w.z;
                    gl_Position=vec4(rtwsmWarp(p.xy),p.z,p.w);
                    glcolor1=glcolor[0]*w.x+glcolor[1]*w.y+glcolor[2]*w.z;
                    texcoord1=texcoord[0]*w.x+texcoord[1]*w.y+texcoord[2]*w.z;
                    snormal1=snormal[0]*w.x+snormal[1]*w.y+snormal[2]*w.z;
                    EmitVertex();
                }
                EndPrimitive();
            }
        }
    }
}