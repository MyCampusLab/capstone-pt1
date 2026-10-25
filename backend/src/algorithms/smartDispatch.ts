/**
 * Smart Dispatch (Task Allocation) Engine for Barbershop Multi-Tenant
 * 
 * Balances workload across active barbers in the selected tenant
 * when customers choose "Kapster Bebas / Mana Saja Cepat".
 */

export interface ActiveBarber {
  id: number;
  name: string;
  chair_number: number;
  speed_factor?: number;
  speed_val?: number;
}

export interface ActiveQueueItem {
  id: number;
  barber_id: number;
  status: string;
  estimated_duration: number;
  estimated_start_time: string | Date;
}

export interface BarberWorkload {
  barber: ActiveBarber;
  activeQueueCount: number;
  totalDurationBacklogMinutes: number;
  latestEstimatedFinish: Date;
}

export interface DispatchAllocationResult {
  assignedBarber: ActiveBarber;
  estimatedStartTime: string;
  estimatedEndTime: string;
  queueStartWaitMinutes: number;
  projectedFinishMinutes: number;
  allBarberWorkloads: Array<{
    barberId: number;
    barberName: number | string;
    chair: number;
    activeQueues: number;
    backlogMinutes: number;
    latestFinish: string;
  }>;
}

export class SmartDispatchEngine {
  /**
   * Determine the optimal barber assignment based on lowest cumulative queue workload
   */
  static allocateQueue(
    activeBarbers: ActiveBarber[],
    currentActiveQueues: ActiveQueueItem[],
    newServiceEstimatedDuration: number,
    bufferTimeMinutes: number = 5,
    referenceTime: Date = new Date()
  ): DispatchAllocationResult {
    if (!activeBarbers || activeBarbers.length === 0) {
      throw new Error('Tidak ada kapster yang aktif/bertugas di cabang ini (Zero active barbers).');
    }

    // 1. Group active queues by barber_id and compute total minutes backlog
    const barberWorkloads: BarberWorkload[] = activeBarbers.map((barber) => {
      const barberQueues = currentActiveQueues.filter(
        (q) => q.barber_id === barber.id && (q.status === 'waiting' || q.status === 'in_service' || q.status === 'checked_in')
      );

      let totalBacklog = 0;
      let latestFinish = new Date(referenceTime.getTime());

      for (const q of barberQueues) {
        const estStart = new Date(q.estimated_start_time);
        const estEnd = new Date(estStart.getTime() + q.estimated_duration * 60000);

        if (estEnd > latestFinish) {
          latestFinish = estEnd;
        }

        const remainingMinutes = Math.max(0, Math.ceil((estEnd.getTime() - referenceTime.getTime()) / 60000));
        totalBacklog += remainingMinutes;
      }

      if (barberQueues.length > 0) {
        latestFinish = new Date(latestFinish.getTime() + bufferTimeMinutes * 60000);
      }

      return {
        barber,
        activeQueueCount: barberQueues.length,
        totalDurationBacklogMinutes: totalBacklog,
        latestEstimatedFinish: latestFinish,
      };
    });

    // 2. Select the barber with the minimum backlog
    // Tie-breaking: 1) Lowest workload minutes, 2) Lowest queue count, 3) Chair number
    barberWorkloads.sort((a, b) => {
      if (a.totalDurationBacklogMinutes !== b.totalDurationBacklogMinutes) {
        return a.totalDurationBacklogMinutes - b.totalDurationBacklogMinutes;
      }
      if (a.activeQueueCount !== b.activeQueueCount) {
        return a.activeQueueCount - b.activeQueueCount;
      }
      return a.barber.chair_number - b.barber.chair_number;
    });

    const selected = barberWorkloads[0]!;

    // 3. Compute incoming customer start and finish times
    const estimatedStartTime = new Date(selected.latestEstimatedFinish.getTime());
    const estimatedEndTime = new Date(
      estimatedStartTime.getTime() + newServiceEstimatedDuration * 60000
    );

    const queueStartWaitMinutes = Math.max(
      0,
      Math.ceil((estimatedStartTime.getTime() - referenceTime.getTime()) / 60000)
    );

    const projectedFinishMinutes = queueStartWaitMinutes + newServiceEstimatedDuration;

    return {
      assignedBarber: selected.barber,
      estimatedStartTime: estimatedStartTime.toISOString(),
      estimatedEndTime: estimatedEndTime.toISOString(),
      queueStartWaitMinutes,
      projectedFinishMinutes,
      allBarberWorkloads: barberWorkloads.map((bw) => ({
        barberId: bw.barber.id,
        barberName: bw.barber.name,
        chair: bw.barber.chair_number,
        activeQueues: bw.activeQueueCount,
        backlogMinutes: bw.totalDurationBacklogMinutes,
        latestFinish: bw.latestEstimatedFinish.toISOString(),
      })),
    };
  }
}
