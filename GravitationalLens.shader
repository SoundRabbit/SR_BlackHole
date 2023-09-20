Shader "SoundRabbit/GravitationalLens"
{
    Properties {

        [MainColor]
        _Color ("Color of Black Hole", Color) = (0, 0, 0, 1)
        _PhotonRingColor ("Color of Photon Ring", Color) = (1, 1, 0.5, 1)

        _Rad ("Radius", Float) = 0.35
        _Ord ("Order", Float) = 1.0
        _Bas ("Base", Float) = 2.0
        _Cor ("Radius Ratio for Cutoff", Float) = 0.99

        [Enum(UnityEngine.Rendering.CullMode)]
        _Cull ("Cull", Float) = 2
        
        [Toggle(_RENDER_AS_BILLBOARD)]
        _RenderAsBillboard ("Render as Billboard", Float) = 1
        
        [Toggle(_Z_SIMULATE)]
        _ZSimulate ("Simulate Z", Float) = 0
        
        [Toggle(_USE_EXPO)]
        _UseExpo ("Use Exponential", Float) = 0
        
        [Toggle(_CALC_IN_FRAG)]
        _CalcInFrag("Calculate in Fragment Shader", Float) = 0
    }

    SubShader
    {
        Tags { "Queue" = "Transparent+1000" "RenderType" = "Opaque" "VRCFallback" = "Unlit" }

        CGINCLUDE
        ENDCG

        GrabPass {}

        Pass
        {
            Cull [_Cull]
            ZWrite On
            ZTest LEqual

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _USE_EXPO
            #pragma multi_compile _ _CALC_IN_FRAG
            #pragma multi_compile _ _RENDER_AS_BILLBOARD
            #pragma multi_compile _ _Z_SIMULATE

            #include "UnityCG.cginc"

            #define PI 3.1415926535897932384626433832795

            float _Cull;
            float _RenderAsBillboard;

            float4 _Color;
            float4 _PhotonRingColor;

            float _Rad;
            float _Ord;
            float _Bas;
            float _Cor;
            
            float _UseExpo;
            float _CalcInFrag;

            sampler2D _GrabTexture;

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 grabPos : TEXCOORD0;
                float4 pos : SV_POSITION;
                float3 p: POSITION1;
                float aspect: TEXCOORD1;

                float r: TEXCOORD2;

                float3 viewPos: POSITION2;
                float3 viewOriginPos: POSITION3;
            };

            struct fragOutput
            {
                float4 color : SV_Target;
                
                #if defined(_Z_SIMULATE) && defined(_CALC_IN_FRAG)
                    float depth : SV_Depth;
                #endif
            };

            v2f vert (appdata v)
            {
                v2f o;

                // ビュー空間での位置を計算
                float3 viewOriginPos = UnityObjectToViewPos(float4(0, 0, 0, 1));
                #if defined(_RENDER_AS_BILLBOARD)
                    float3 scaleRotatePos = mul((float3x3)unity_ObjectToWorld, v.vertex);
                    float3 viewPos = viewOriginPos + float3(scaleRotatePos.xy, -scaleRotatePos.z);
                #else
                    float3 viewPos = UnityObjectToViewPos(v.vertex);
                #endif

                // クリップ空間での位置を計算
                o.pos = mul(UNITY_MATRIX_P, float4(viewPos, 1));

                // GrabPassの座標を計算
                o.grabPos = ComputeGrabScreenPos(o.pos);

                #if defined(_CALC_IN_FRAG)
                    o.viewPos = viewPos;
                    o.viewOriginPos = viewOriginPos;
                #else
                    // 中心からの距離を計算
                    float r0 = length(viewPos - viewOriginPos);
                    float r1 = unity_OrthoParams[3] == 1 ?
                        length(viewPos.xy - viewOriginPos.xy) :
                        length(cross(viewOriginPos, viewPos)) / length(viewOriginPos);
                    o.r = r0 == 0 ? 0 : clamp(r1 / r0, 0, 1);

                    // 深度を計算
                    #if defined(_Z_SIMULATE)
                        float depth =
                            o.r > _Rad ?
                                viewPos.z - viewOriginPos.z :
                                sqrt(pow(r0 * _Rad, 2) - pow(r1, 2));
                        depth = viewPos.z < viewOriginPos.z ? -depth : depth;

                        float4 clipPos =  mul(UNITY_MATRIX_P, float4(viewPos.xy, viewOriginPos.z + depth, 1));

                        o.pos.z = clipPos.z / clipPos.w * o.pos.w;
                    #endif
                #endif

                // クリップ空間での中心からのずれを計算
                float4 clipOriginPos = UnityObjectToClipPos(float4(0, 0, 0, 1));
                o.p = o.pos.xyz / o.pos.w - clipOriginPos.xyz / clipOriginPos.w;
                o.p.y *= -1;

                // カメラアスペクト比を計算
                float4 projectionSpaceUpperRight = float4(1, 1, UNITY_NEAR_CLIP_VALUE, _ProjectionParams.y);
                float4 viewSpaceUpperRight = mul(unity_CameraInvProjection, projectionSpaceUpperRight);
                o.aspect = viewSpaceUpperRight.x / viewSpaceUpperRight.y;

                return o;
            }

            fragOutput frag (v2f i)
            {
                fragOutput o;

                float ir;
                #if defined(_CALC_IN_FRAG)
                    // 中心からの距離を計算
                    float r0 = length(i.viewPos - i.viewOriginPos);
                    float r1 = unity_OrthoParams[3] == 1 ?
                        length(i.viewPos.xy - i.viewOriginPos.xy) :
                        length(cross(i.viewOriginPos, i.viewPos)) / length(i.viewOriginPos);
                    ir = r0 == 0 ? 0 : clamp(r1 / r0, 0, 1);

                    // 深度を計算
                    #if defined(_Z_SIMULATE)
                        float depth =
                            ir > _Rad ?
                                i.viewPos.z - i.viewOriginPos.z :
                                sqrt(pow(r0 * _Rad, 2) - pow(r1, 2));
                        depth = i.viewPos.z < i.viewOriginPos.z ? -depth : depth;

                        float4 clipPos =  mul(UNITY_MATRIX_P, float4(i.viewPos.xy, i.viewOriginPos.z + depth, 1));
                        
                        o.depth = clipPos.z / clipPos.w;
                    #endif
                #else
                    ir = i.r;
                #endif

                // 中心からの距離を補正
                ir = smoothstep(0, _Cor, ir);

                // 屈折角を計算（カメラには平行光として入ると仮定）                
                #if defined(_USE_EXPO)
                    ir = clamp((pow(_Bas, ir) - 1) / (_Bas - 1), 0, 1);
                    float ra = clamp((pow(_Bas, _Rad) - 1) / (_Bas - 1), 0, 1);
                    float rt = (PI * ra) / (2 - 2 * ra);
                #else
                    ir = pow(ir, _Ord);
                    float ra = pow(_Rad, _Ord);
                    float rt = (PI * ra) / (2 - 2 * ra);
                #endif

                float refractionAngle = max(0, rt / ir - rt);
                float refractionDist = tan(refractionAngle);
                float2 offsetDir = refractionDist * normalize(i.p.xy);

                // GrabPassの座標をずらす
                float4 grabPos = i.grabPos;
                grabPos.x -= offsetDir.x / i.aspect * grabPos.w;
                grabPos.y -= offsetDir.y * grabPos.w;

                //光子球の色を計算
                refractionDist = abs(refractionDist);
                float4 photonRingColor =
                    float4(refractionDist, refractionDist, refractionDist, 1)
                    * _PhotonRingColor;
                photonRingColor = max(photonRingColor, 1);

                // 色を計算
                o.color =
                    refractionAngle > PI / 2 ?
                        _Color :
                        tex2Dproj(_GrabTexture , grabPos) * photonRingColor;

                return o;
            }
            ENDCG
        }
    }

    CustomEditor "SR_BlackHole.ShaderEditor"
}
