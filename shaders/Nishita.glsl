-- Vertex

// IN
layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal;
layout (location = 2) in vec2 inTexcoords;

// Out
out vec2 vTexcoords;
out vec3 vNormalW;

uniform vec3 uCameraPosition;
uniform mat4 uModelToProj;

void main()
{
    vec4 position = uModelToProj*vec4(inPosition + uCameraPosition, 1.0);
    gl_Position = position;
    vTexcoords = inTexcoords;
    vNormalW = -inPosition;
}

-- Fragment

#define SUN_ENABLE 1
// Experimental:
#define RAYLEIGH_SCTR_ONLY_ENABLE 0

#include "Common.glsli"
#include "Math.glsli"
#include "PhaseFunctions.glsli"

// IN
in vec2 vTexcoords;
in vec3 vNormalW;

// OUT
out vec4 fragColor;

const int numScatteringSamples = 16;
const int numLightSamples = 8;
const int numSamples = 4;

// [Hillaire16] use 1.11 factor 
// [Preetham99] Mie coefficient ratio scattering / (absorption+scattering) is about to 0.9
// http://publications.lib.chalmers.se/records/fulltext/203057/203057.pdf use 1/0.9
const float mieScale = 1.11;

// big number
const float inf = 9.0e8;
const float Hr = 7994.0;
const float Hm = 1220.0;
const float g = 0.760;
// 1 m
const float humanHeight = 1.0;

// https://ozonewatch.gsfc.nasa.gov/facts/ozone.html
// https://en.wikipedia.org/wiki/Number_density
// Ozone scattering with its mass up to 0.00006%, 0.00006 is standard
// Ozone scattering with its number density up to 2.5040, 2.5040 is standard
const vec3 mOzoneMassParams = vec3(0.6e-6, 0.0, 0.9e-6) * 2.504;
const float mOzoneMass = mOzoneMassParams.x;

// http://www.iup.physik.uni-bremen.de/gruppen/molspec/databases/referencespectra/o3spectra2011/index.html
// Version 22.07.2013: Fast Fourier Transform Filter applied to the initial data in the region 213.33 -317 nm 
// Ozone scattering with wavelength (680nm, 550nm, 440nm) and 293K
const vec3 mOzoneScatteringCoeff = vec3(1.36820899679147, 3.31405330400124, 0.13601728252538);

uniform bool uChapman;
uniform float uEarthRadius; 
uniform float uAtmosphereRadius;
uniform float uAspect;
uniform float uAngle;
uniform float uAltitude;
uniform float uTurbidity;
uniform float uSunRadius;
uniform float uSunRadiance;
uniform vec2 uInvResolution;
uniform vec3 uEarthCenter;
uniform vec3 uSunDir;
uniform vec3 uSunIntensity;
uniform vec3 uCameraPosition;
uniform vec3 betaR0; // vec3(5.8e-6, 13.5e-6, 33.1e-6);
uniform vec3 betaM0; // vec3(21e-6);
// [Hillaire16]
uniform vec3 betaO0 = vec3(3.426, 8.298, 0.356) * 6e-7;


// Ref. [Schuler12]
//
// this is the approximate Chapman function,
// corrected for transitive consistency
float ChapmanApproximation(float X, float h, float coschi)
{
	float c = sqrt(X + h);
	if (coschi >= 0.0)
	{
		return	c / (c*coschi + 1.0) * exp(-h);
	}
	else
	{
		float x0 = sqrt(1.0 - coschi*coschi)*(X + h);
		float c0 = sqrt(x0);
		return 2.0*c0*exp(X - x0) - c/(1.0 - c*coschi)*exp(-h);
	}
}

bool opticalDepthLight(vec3 s, vec2 t, out float rayleigh, out float mie)
{
	if (!uChapman)
	{
		// start from position 's'
		float lmin = 0.0;
		float lmax = t.y;
		float ds = (lmax - lmin) / numLightSamples;
		float r = 0.f;
		float m = 0.f;
		for (int i = 0; i < numLightSamples; i++)
		{
			vec3 x = s + ds*(0.5 + i)*uSunDir;
			float h = length(x) - uEarthRadius;
			if (h < 0) return false;
			r += exp(-h/Hr)*ds;
			m += exp(-h/Hm)*ds;
		}
		rayleigh = r;
		mie = m;
		return true;
	}
	else
	{
		// approximate optical depth with chapman function  
		float x = length(s);
		float Xr = uEarthRadius / Hr; 
		float Xm = uEarthRadius / Hm;
		float coschi = dot(s/x, uSunDir);
		float xr = x / Hr;
		float xm = x / Hm;
		float hr = xr - Xr;
		float hm = xm - Xm;
		rayleigh = Hr * ChapmanApproximation(Xr, hr, coschi);
		mie = Hm * ChapmanApproximation(Xm, hm, coschi);
		return true;
	}
}

// [ScratchPixel]
vec3 computeIncidentLight(vec3 pos, vec3 dir, vec3 intensity, float tmin, float tmax)
{
    vec2 t = ComputeRaySphereIntersection(pos, dir, uEarthCenter, uAtmosphereRadius);

    tmin = max(t.x, tmin);
    tmax = min(t.y, tmax);

    if (tmax < 0)
        discard;

    // see pig.8 in scratchapixel
    // tc: camera position
    // pb: tc (tmin is 0)
    // pa: intersection point with atmosphere
    vec3 tc = pos;
    vec3 pa = tc + tmax*dir;
    vec3 pb = tc + tmin*dir;

    float opticalDepthR = 0.0;
    float opticalDepthM = 0.0;
    float ds = (tmax - tmin) / numScatteringSamples; // delta segment

    vec3 sumR = vec3(0, 0, 0);
    vec3 sumM = vec3(0, 0, 0);

    //
    // equation 2 through 4
    // 
    // note: beta = extinction coefficients
    //
    // T(Pa, Pb) = La/Lb = exp(-integral(beta(h) * ds)))
    //
    // beta(h) = beta(0)*exp(-h/H)
    //
    for (int s = 0; s < numScatteringSamples; s++)
    {
        vec3 x = pb + ds*(0.5 + s)*dir;
        float h = length(x) - uEarthRadius;
        float betaR = exp(-h/Hr)*ds;
        float betaM = exp(-h/Hm)*ds;
        opticalDepthR += betaR;
        opticalDepthM += betaM;
        
        // find intersect sun lit with atmosphere
        vec2 tl = ComputeRaySphereIntersection(x, uSunDir, uEarthCenter, uAtmosphereRadius);

        // light delta segment 
        float opticalDepthLightR = 0.0;
        float opticalDepthLightM = 0.0;

        if (!opticalDepthLight(x, tl, opticalDepthLightR, opticalDepthLightM))
            continue;
        
    #if RAYLEIGH_SCTR_ONLY_ENABLE
        // But, in 'Time of day.conf' state that ozone also has small scattering factor
        // And use rayleigh beta only
        vec3 lambda = betaR0 + betaM0 + mOzoneScatteringCoeff * mOzoneMass;
        vec3 tau = lambda * (opticalDepthR + opticalDepthLightR);
        vec3 attenuation = exp(-(tau));
    #else
        // It claims that ozone has 0 scattering (absorption only) [Gustav14](above eq.8)
        // and beta is similar to betaR (= with similar distribution) [Hillaire16]
        // so, reuse optical depth for rayleigh
        vec3 tauO = betaO0 * (opticalDepthR + opticalDepthLightR);
        vec3 tauR = betaR0 * (opticalDepthR + opticalDepthLightR);
        vec3 tauM = mieScale * betaM0 * (opticalDepthM + opticalDepthLightM);
        vec3 attenuation = exp(-(tauR + tauM + tauO));
    #endif
        sumR += attenuation * betaR;
        sumM += attenuation * betaM;
    }

    float mu = dot(uSunDir, dir);
    float phaseR = ComputePhaseRayleigh(mu);
    float phaseM = ComputePhaseMie(mu, g);
    return intensity * (sumR*phaseR*betaR0 + sumM*phaseM*betaM0);
}

vec3 GetTransmittance(vec3 x, vec3 V)
{
    vec2 tl = ComputeRaySphereIntersection(x, uSunDir, uEarthCenter, uAtmosphereRadius);

    float opticalDepthLightR = 0.0;
    float opticalDepthLightM = 0.0;
    opticalDepthLight(x, tl, opticalDepthLightR, opticalDepthLightM);

#if RAYLEIGH_SCTR_ONLY_ENABLE
	return exp(-(betaR0 + betaM0) * opticalDepthLightR);
#else
    vec3 tauR = (betaO0 + betaR0) * opticalDepthLightR;
    vec3 tauM = mieScale * betaM0 * opticalDepthLightM;
    return exp(-(tauR + tauM));
#endif
}

// ----------------------------------------------------------------------------
void main() 
{
    vec3 dir = normalize(-vNormalW);

    vec3 cameraPos = vec3(0.0, humanHeight + uAltitude + uEarthRadius, 0.0);
    vec2 t = ComputeRaySphereIntersection(cameraPos, dir, uEarthCenter, uEarthRadius);
    // handle ray toward ground
    float tmax = inf;
    if (t.y > 0) tmax = max(0.0, t.x);

    vec3 sunIntensity = vec3(uSunRadiance);
    vec3 color = computeIncidentLight(cameraPos, dir, sunIntensity, 0.0, tmax);

#if SUN_ENABLE
    float phaseTheta = dot(dir, uSunDir);
	float intersectionTest = float(t.x < 0.0 && t.y < 0.0);
    float angle = saturate((1 - phaseTheta) * sqrt(abs(uSunDir.y)) * uSunRadius);
    float cosAngle = cos(angle * PI * 0.5);
    float edge = ((angle >= 0.9) ? smoothstep(0.9, 1.0, angle) : 0.0);;

    // Model from http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
    vec3 u = vec3(1.0, 1.0, 1.0) ; // some models have u!=1
    vec3 a = vec3(0.397, 0.503, 0.652) ; // coefficient for RGB wavelength (680 ,550 ,440)

    float mu = sqrt(1.0 - angle*angle);
    vec3 factor = 1.0 - u*(1.0 - pow(vec3(mu), a));

    vec3 limbDarkening = GetTransmittance(cameraPos, dir) * factor * intersectionTest;
    limbDarkening *= pow(vec3(cosAngle), vec3(0.420, 0.503, 0.652)) * mix(vec3(1.0), vec3(1.2,0.9,0.5), edge) * intersectionTest;
    color += limbDarkening;
#endif

    fragColor = vec4(color, 1.0);
}

