#version 430 compatibility

uniform sampler2D tex;

in vec4 glcolor1;
in vec2 texcoord1;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

const int shadowMapResolution = 2048;
const float shadowDistance = 192.0;

void main(){
    vec4 albedo=texture(tex,texcoord1)*glcolor1;

    if(albedo.a<.1){
        discard;
    }

    color=vec4(albedo.rgb,albedo.a);
}