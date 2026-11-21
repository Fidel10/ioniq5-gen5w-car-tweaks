# Sensor and state catalogue

Status: **derived from the owner's `260128` firmware and live observation**.
Names and IDs come from the vendor's CAN/logging map and the factory QML
models; bit layouts and scales are not all validated. This is a map, not a
DBC, and not a promise that every signal exists on every trim/firmware.
Values below are examples/units, not the owner's current data.

## Bus map

| Path | Carries | How to read |
|---|---|---|
| `can0` / `can1` (I-CAN) | BMS, OBC/VCMS, VCU, climate, TPMS, doors, lamps, speed, odometer | raw CAN socket; use the battery daemon `--sniff` (check which interface your unit uses) |
| M-CAN | body, ICU/12 V, schedules, some BMS detail | not on the head unit's I-CAN; via the micom (`SetExtMMCanTxReq`/`AskExtMMCanReq`) or the factory models |
| Factory QML models | values already decoded by the vendor | `AppPHEVModel`, `appClimateModel`, `AppNModeModel`, `AppSettingModel` |
| Micom D-Bus | commands and some queries | `com.lge.car.micom`, `/Can`, `/Ihu`; read the upstream command docs first |

Do not send unknown micom `Set…` commands. The micom manager checks the
sender and the vehicle may react.

## High-voltage battery / BMS

| Signal | ID / source | Meaning | Notes |
|---|---|---|---|
| `xEV_SocDis` | I-CAN `0x2FC` | display SoC | the daemon uses byte 7 / 2 |
| minimum cell temperature | I-CAN `0x2FC` byte 2 | °C of the coldest cell | **only min**; no max |
| `xEV_SocVal` | I-CAN `0x237` | raw BMS SoC | can differ from display |
| `xEV_BatEvtAlarm` | I-CAN `0x237` | BMS alarm/event | bits not fully decoded |
| `CR_Bms_Soc_Pc` | I-CAN `0x594` | BMS SoC % | |
| `CR_Bms_DisplaySoc` | EV GW `0x55D`/`0x5D8` | display SoC | |
| `VCRM_SocDisplayVal` | I-CAN `0x336` | VCRM display SoC + fault | |
| `CR_Bms_EvEnergyCapa` | EV GW `0x56D` | energy capacity | scale TBD |
| `EV_Batt_Cell_Type` | EV GW `0x57D` | cell type code | |
| `xEV_Bms_GDS_SOH` | `0x1405502` (extended, 500 ms) | SOH via GDS | **unverified** on this car |
| `xEV_BatHeatPwrSum_Wh` | I-CAN `0x25D` | battery heater energy | counter |
| `EV_BatteryConditioning` | BMS `0x25D` | conditioning state | setting/state |

## 12 V auxiliary battery / ICU

These are **SoC/state/thresholds**, not a voltage measurement:

| Signal | ID / source | Meaning |
|---|---|---|
| `BAT_SOC`, `BAT_SNSR_State` | `0x169`, `0x549` | 12 V battery sensor SoC/state |
| `BAT_SocVal`, `BAT_AuxBattOpt` | `0x136` | SoC / auxiliary battery option |
| `CR_Bms_12V_AuxBattOpt` | `0x499` | 12 V aux option/state |
| `ICU_BS2SoC` | `0x338`, `0x410` | ICU battery SoC |
| `Batt_SoC`, `C_BattMngAlert` | `0x19F`, `0x15C` | SoC / management alert |
| `Batt_SoCWarningValue`, `Batt_SoCAlertValue` | `0x337`, `0x48F`, `0x19F` | warning/alert thresholds |
| `ICU_BattAutoCutPreWrng`, `ICU_PowerAutoCutModSta` | `0x337`, `0x33A`, `0x418` | auto-cut pre-warning/mode |
| `ICU_BattMngAlert` | `0x405` | ICU battery alert |
| `VCRM_SysFltSta` | `0x336` | VCRM fault status |

The page/models do **not** expose a 12 V voltage value. If you need volts,
measure it separately or find a diagnostic/UDS path.

## Charging / OBC / EVSE

| Signal | ID / source | Meaning |
|---|---|---|
| `CHRG_ChrgSta`, `CHRG_StndChrgSta` | I-CAN `0x326` | charging state |
| `CHRG_NorChgFnshSta`, `CHRG_ChrgFnshSta` | `0x326` | normal/charge finished |
| `CHRG_StndChrgRmnTimeVal` | `0x326`/`0x327` | standard remaining time |
| `CHRG_RealStndChrgRmnTimeVal` | `0x326`/`0x329` | real remaining time |
| `CHRG_EuroStndChrgRmnTimeVal` | `0x326`/`0x329` | European standard time |
| `CHRG_StndChrgRmnTime120Val` | `0x328` | 120 V time |
| `CHRG_StndChrgConnSta_120V` | `0x326` | 120 V connection |
| `scChgRemainedTime_Min` | `0x55D`/`0x5D8` | slow-charge remaining time |
| `qcChgRemainedTime` | `0x56A`/BMS23 | fast-charge remaining time |
| `VCRM_QckChrgRmnTimeVal`, `VCRM_StndChrgRmnTime*` | `0x1F7`, `0x1F9` | VCRM times |
| `CF_Bms_StdCha`, `CF_Bms_ChgSts` | `0x5D8` | BMS charge state |
| `CHRG_ScChgTargetSOCSync`, `CHRG_QcChgTargetSOCSync` | `0x333`, `0x334` | target SoC slow/fast |
| `CF_OBC_PD_Stat`, `CF_OBC_EVSE_RDY_STATE` | I-CAN `0x57F` | PD / EVSE ready |
| `CF_OBC_ACChargingStat`, `CF_OBC_DCChargingStat` | `0x57F` | AC/DC charging |
| `CF_OBC_FLT` | `0x57F` | OBC fault |
| `VCMS_PDStatus`, `VCMS_AC/DCChargingStat` | I-CAN `0x30B` | VCMS states |
| `VCMS_EvseRdyStat`, `VCMS_ChgFinished`, `VCMS_Rdy` | `0x30B` | EVSE/finished/ready |
| `VCMS_ChgAlarm_Stat/Subcode` | `0x30D` | charge alarms |
| `VCMS_ChgPwrDerating` | `0x30C` | charge power derating |
| `VCMS_V2GMode`, `VCMS_V2LMode` | `0x30E` | V2G/V2L modes |
| `VCMS_V2XDisOpFlag` | `0x322` | V2X discharge flag |
| `VCMS_V2LEstDischgRmnTime` | `0x324`/`0x57E` | V2L estimated time |

## Drive / vehicle

| Signal | ID / source | Meaning |
|---|---|---|
| `VCU_EVDrvRdySta`, `VCU_GearPosSta`, `VCU_RdySta` | I-CAN `0x036` | ready/gear/READY |
| `TCU_GearSlctDis`, `HTCU_GearSlctrDis` | `0x041`, `0x046` | gear selector |
| `CF_Vcu_EvRdy`, `CF_Vcu_GarSelDisp` | `0x200` | ready/gear |
| `CLU_DisSpdVal`, `CF_Clu_Vanz`, `CF_Clu_DisplaySpeed` | `0x1AB`, `0x450`, `0x52A` | speed |
| `CLU_OdoVal`, `CF_Clu_Odometer` | `0x226`, `0x227`, `0x5D0` | odometer |
| `CF_Clu_DTE`, `CLU_DTEVal`, `CF_Clu_EVDTEDisp` | `0x50C`, `0x226`, `0x1D1` | range/DTE |
| `HCU_EVModDTEKmVal` | `0x22C` | EV DTE km |
| `VCU_DteBaseVal`, `VCU_DteOffDispSta` | `0x2B7`, `0x2B6` | DTE base/off |
| `VCU_UtilModeUsmSta` | `0x2AE` | Utility mode |
| `CLU_DrvngModSwSta` | `0x593` | drive-mode switch |

## Climate (DATC + `appClimateModel`)

| Signal | ID / source | Meaning |
|---|---|---|
| `CR_Datc_DrTempDispC/F`, `CF_DATC_TempDisp_Sts` | `0x42`, `0x380`, `0x5C4` | driver temperature/display |
| `CF_Datc_TempDispUnit` | `0x382`, `0x5C4` | C/F unit |
| `CF_Datc_FrDefLed`, `DATC_FrDfgSta` | `0x43`, `0x383` | front defog |
| `FrBlwDisp`, `DATC_FrDrvBlwDis`, `CF_Fatc_FrontBlrStep` | `0x43`, `0x384`, `0x56A` | blower |
| `DATC_AcnCompFltSta` | `0x147` | A/C compressor fault |
| `DATC_PtcFltSta`, `DATC_PtcTyp` | `0x1B1`, `0x31B` | PTC fault/type |
| `DATC_MainBlowerDisp_MCAN` | `0x132` | blower display |

`appClimateModel` (already decoded by the vendor) exposes ambient
temperature (`ambienTemp`), set points (`levelDriver`, `levelPassenger`,
`levelRear`, `valueTempRear`), blower, AC/auto, defog, air cleaning/CO2,
seat heating/ventilation, steering-wheel heating, smart vent, tunnel
detection, washer fluid and diagnostics. It does **not** expose a measured
cabin temperature.

## Body, doors, windows, seats, lamps

| Signal | ID / source | Meaning |
|---|---|---|
| `Open-DD,AD,RL,RR,Tr,Hood`, `Unlock-*` | `0x168`, `0x103`, `0x15D`, `0x17F` | doors/trunk/hood open & locked |
| `DoorLock_*`, `Warn_*DrSwSta`, `HoodSwSta`, `BrkFldSwSta` | `0x315` | locks, door/hood switches, brake fluid |
| `Trunk_TrnkTlgtSwSta`, `Defog_DfgrRlySta`, `Mirror_FldngOptSta` | `0x318` | trunk, defog relay, mirrors |
| `C_SunroofOpenState`, `BCM_SunRoofOpnSta`, `SunRoof` | `0x103`, `0x308`, `0x17F` | sunroof |
| `Window_*ActSta/DetailOpnSta`, `DrvWin/AstWin/RLWin/RRWin` | `0x1A0`, `0x33F`, `0x17F`, `0x30A` | windows |
| `*_SHVU_SeatHtOperSta`, `SeatOptSta` | `0x323`, `0x324`, `0x350`, `0x357` | seat heat/option |
| `StrgWhlHeatedState`, `HeatedSteerWheel_*`, `C_StrgWhlHeatingOpt` | `0x107`, `0x19F`, `0x33A`, `0x15E` | steering-wheel heat |
| `Fob_BattStaInfo` | `0x333` | key-fob battery |
| `BAlarm*` | `0x100`, `0x303` | burglar alarm |
| `Mirror_OSMirFldOpt/Dis`, `C_OSMirrorStatus` | `0x401`, `0x1EB`, `0x30A` | folding mirrors |
| `Lamp_StpLmp*`, `Lamp_HdLmp*`, `Lamp_*TrnSig*`, `CF_Afls_LedHLStat` | `0x412`, `0x413`, `0x416`, `0x417`, `0x7F` | lamps |
| `Warn_WshrFldSwSta`, `C_IBU_WasherSw` | `0x411`, `0x50E` | washer fluid/switch |
| `Warn_DrvStBltSwSta`, `Warn_AsstStBltSwSta` | `0x411` | seat belts |
| `Warn_RrStRmnd*`, `ROA_*` | `0x32F`, `0x3E2`, `0x3C0` | rear occupant alert |

## TPMS, chassis, schedules

| Signal | ID / source | Meaning |
|---|---|---|
| `TREAD_W_LAMP`, `FL`, `FR`, `RL`, `RR` | `0x3A1`, `0x578`, `0x593` | tyre pressures + warning |
| `TPMS_TreadWrngLmpSta`, `TPMS_WrngLmpSta` | `0x3A2` | TPMS warnings |
| `AVH_LmpDis`, `AVH_LAMP` | `0x57A`, `0x169` | Auto Vehicle Hold |
| `VCU_DepartSet1/2_*` | `0x2AB`, `0x56C`, `0x5AD` | departure schedules |
| `SchedChgSt_*`, `SchedChgEnd_*` | `0x57D`, `0x234`, `0x2AD` | charge schedule |
| `VCU_OffPeakTime*`, `HCU_EcoChrg*` | `0x2AC`, `0x233` | off-peak/eco charging |
| `DepartSet1_PreConSet/TempSet/DefrostCtr` | `0x56C` | scheduled preconditioning |

## Factory model property groups

`AppPHEVModel` (188 properties used by the UI) includes:

- **Battery/charge:** `batLevel`, `display_Batlevel`, `batChgSts`,
  `fastChgSts`, `stdChgSts`, `batChgLvlFast/Normal`, `currentBatChgLvl`,
  `fastChgRemTime`, `stdChgRemTime`, `portChgRemTime`,
  `realScChgRemTime`, `fastChgRemTimeCustom`, `dte_QcChg`, `dte_ScChg`,
  `batterySegment`, `batteryConditionMode`, `winterMode`,
  `winterModeAvailable`, `lowBatteryWarnType`, `percentLowSoc`.
- **Energy/power:** `pwrInstantBattery`, `pwrInstantHeat`,
  `pwrInstantDrivingKw`, `pwrInstantEclectric`, `consumptionPower`,
  `avgMGPwr`, `listAvgMGPwr`, `batCapacity`, `heatBatteryPercent`, `CO2Rdc`.
- **V2L/V2G:** `dischargingLevel`, `V2LDischargeTime`, `V2GState`,
  `supportV2G`, `supportV2L`, `V2XDisOpFlag`, `powerInUseV2L`,
  `settingV2XDisChargeLvCondition`, `isShowV2XFastChargeTargetSOC`.
- **Range/trip:** `DTE`, `display_DTE`, `dteAdd`, `dteOffDisp`, `totalDTE`,
  `tripDistance`, `ecodrivingHistory`, `ecoModel`, `rangeUnit`.
- **Climate/schedules:** `climateSts`, `climatePercent`, `climateDefrost`,
  `isClimateOnTimerActive`, `isClmScheValid`, `scheChrgState`,
  `scheClmtState`, `nextDepart*`, `begExpectedTime`, `endExpectedTime`.

`appClimateModel` covers climate, seats, steering wheel, purification, CO2,
tunnels and diagnostics (see above).

## What is not available

- **Maximum/average cell temperature** — only the minimum on `0x2FC`.
- **Per-cell voltages, pack voltage, isolation resistance, leakage** — not
  in the exposed map/models.
- **12 V voltage** — only SoC/state/thresholds.
- **SOH** — an extended GDS frame exists (`0x1405502`) but is unvalidated
  and not exposed by the models.
- **Charge cycle counts / lifetime kWh** — not found.
- **Cabin air temperature** — not exposed; `levelDriver` is a set point.

## How to go deeper

1. Put the car in READY (not just ignition) and run the battery daemon
   `--sniff 60`; a parked/sleeping car can show only a couple of gateway
   IDs.
2. Repeat during AC/DC charging to map `0x326`, `0x30B`, `0x57F`, `0x493`,
   `0x5D8`.
3. Prefer the factory QML models for values they already decode; verify a
   new property against the vendor QML that uses it.
4. Do not send micom `Set…` commands without the upstream whitelist and a
   clear reason; `Ask…` queries are safer but still not all documented.
5. Treat the signal map as evidence, not as a DBC: confirm IDs, byte
   offsets and scales on your own car before acting on a value.
