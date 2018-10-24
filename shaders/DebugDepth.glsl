-- Vertex

// IN
layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal;
layout (location = 2) in vec2 inTexcoords;

// Out
out vec2 vTexcoords;

void main()
{
	vTexcoords = inTexcoords;
	gl_Position = vec4(inPosition, 1.0);
}

-- Fragment

// IN
in vec2 vTexcoords;

uniform bool ubOrthographic = false;
uniform float uNearPlane;
uniform float uFarPlane;
uniform sampler2D uTexShadowmap;

// OUT
out vec4 FragColor;

// Required when using a perspective projection matrix
float LinearizeDepth(float depth)
{
    float z = depth * 2.0 - 1.0; // back to ndc
    return (2.0 * uNearPlane * uFarPlane) / (uFarPlane + uNearPlane - z * (uFarPlane - uNearPlane));
}

// ----------------------------------------------------------------------------
void main() 
{
    float depth = float(textureLod(uTexShadowmap, vTexcoords, 0.0));
    if (!ubOrthographic)
        depth = LinearizeDepth(depth);
    FragColor = vec4(vec3(depth), 1.0);
}
