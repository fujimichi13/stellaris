#version 430 compatibility

uniform sampler2D tex;

in vec4 glcolor1;
in vec2 texcoord1;
in vec3 snormal1;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalOut;

const int shadowMapResolution = 2048;
const float shadowDistance = 192.0;

void main(){
    vec4 albedo=texture(tex,texcoord1)*glcolor1;

    if(albedo.a<.1){
        discard;
    }

    color=vec4(albedo.rgb,albedo.a);
    normalOut=vec4(normalize(snormal1)*.5+.5,1.);
}