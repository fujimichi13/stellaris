#version 430 compatibility

uniform sampler2D colortex0;

in vec2 texcoord;

layout(location = 0) out vec4 color;

void main(){
    color=texture(colortex0,texcoord);
}
