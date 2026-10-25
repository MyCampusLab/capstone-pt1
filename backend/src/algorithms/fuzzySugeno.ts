/**
 * Fuzzy Sugeno Engine (Zero-Order) for Barbershop Ecosystem
 * 
 * Input 1: Service Complexity Score (x: 1.0 - 10.0)
 * Input 2: Barber Average Duration (y: 15.0 - 45.0 minutes)
 * Output : Crisp Estimated Duration (Z*: in minutes)
 */

export interface ComplexityMemberships {
  ringan: number;
  sedang: number;
  tinggi: number;
}

export interface SpeedMemberships {
  cepat: number;
  standar: number;
  teliti: number;
}

export interface FuzzyCalculationResult {
  crispDuration: number;
  roundedDuration: number;
  firingStrengths: number[];
  inputComplexity: number;
  inputBarberSpeed: number;
}

export class FuzzySugenoQueueEstimator {
  /**
   * Membership Function for Service Complexity (x: 1.0 to 10.0)
   */
  static getComplexityMemberships(x: number): ComplexityMemberships {
    let ringan = 0;
    if (x <= 2.5) {
      ringan = 1;
    } else if (x > 2.5 && x < 4.5) {
      ringan = (4.5 - x) / (4.5 - 2.5);
    } else {
      ringan = 0;
    }

    let sedang = 0;
    if (x <= 3.0 || x >= 7.5) {
      sedang = 0;
    } else if (x > 3.0 && x <= 5.5) {
      sedang = (x - 3.0) / (5.5 - 3.0);
    } else if (x > 5.5 && x < 7.5) {
      sedang = (7.5 - x) / (7.5 - 5.5);
    }

    let tinggi = 0;
    if (x <= 6.0) {
      tinggi = 0;
    } else if (x > 6.0 && x < 8.0) {
      tinggi = (x - 6.0) / (8.0 - 6.0);
    } else {
      tinggi = 1;
    }

    return { ringan, sedang, tinggi };
  }

  /**
   * Membership Function for Barber Speed / Performance (y: 15 to 45 mins)
   */
  static getSpeedMemberships(y: number): SpeedMemberships {
    let cepat = 0;
    if (y <= 20) {
      cepat = 1;
    } else if (y > 20 && y < 27) {
      cepat = (27 - y) / (27 - 20);
    } else {
      cepat = 0;
    }

    let standar = 0;
    if (y <= 22 || y >= 38) {
      standar = 0;
    } else if (y > 22 && y <= 30) {
      standar = (y - 22) / (30 - 22);
    } else if (y > 30 && y < 38) {
      standar = (38 - y) / (38 - 30);
    }

    let teliti = 0;
    if (y <= 33) {
      teliti = 0;
    } else if (y > 33 && y < 42) {
      teliti = (y - 33) / (42 - 33);
    } else {
      teliti = 1;
    }

    return { cepat, standar, teliti };
  }

  /**
   * Calculate Estimated Duration using 9 Sugeno Rules (Zero-Order)
   */
  static calculateDuration(complexityScore: number, barberAvgDuration: number): FuzzyCalculationResult {
    const clampedComplexity = Math.max(1.0, Math.min(10.0, complexityScore));
    const clampedSpeed = Math.max(15.0, Math.min(45.0, barberAvgDuration));

    const muX = this.getComplexityMemberships(clampedComplexity);
    const muY = this.getSpeedMemberships(clampedSpeed);

    // Rule Base (Zero-Order Sugeno: Constants in minutes)
    const z = [
      15, // R1: Ringan & Cepat
      20, // R2: Ringan & Standar
      25, // R3: Ringan & Teliti
      25, // R4: Sedang & Cepat
      35, // R5: Sedang & Standar
      45, // R6: Sedang & Teliti
      40, // R7: Tinggi & Cepat
      50, // R8: Tinggi & Standar
      65, // R9: Tinggi & Teliti
    ];

    const alpha = [
      Math.min(muX.ringan, muY.cepat),
      Math.min(muX.ringan, muY.standar),
      Math.min(muX.ringan, muY.teliti),
      Math.min(muX.sedang, muY.cepat),
      Math.min(muX.sedang, muY.standar),
      Math.min(muX.sedang, muY.teliti),
      Math.min(muX.tinggi, muY.cepat),
      Math.min(muX.tinggi, muY.standar),
      Math.min(muX.tinggi, muY.teliti),
    ];

    const sumAlpha = alpha.reduce((acc, curr) => acc + curr, 0);
    let weightedSum = 0;

    for (let i = 0; i < 9; i++) {
      weightedSum += alpha[i]! * z[i]!;
    }

    const crisp = sumAlpha === 0 ? 30 : weightedSum / sumAlpha;

    return {
      crispDuration: Number(crisp.toFixed(2)),
      roundedDuration: Math.round(crisp),
      firingStrengths: alpha,
      inputComplexity: clampedComplexity,
      inputBarberSpeed: clampedSpeed,
    };
  }
}
