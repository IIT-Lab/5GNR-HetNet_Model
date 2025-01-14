%This Matlab script is the launcher script for 5GNR heterogeneous model 
%simulation including sub-6 layer of macro cells and above-6(mmW) layer 
%of small cells with CSI acquisition design.
%
%License: This code is licensed under the GPLv2 license.
%
%Script is based on the reference code from the following monograph:
%Emil Bjornson, Jakob Hoydis and Luca Sanguinetti (2017), 
%"Massive MIMO Networks: Spectral, Energy, and Hardware Efficiency", 
%Foundations and Trends in Signal Processing: Vol. 11, No. 3-4, 
%pp. 154-655. DOI: 10.1561/2000000093.
%
%Note: This script require additional software packages to be used, which
%need to be downloaded and installed separately. These packages are
%developed independently and are delivered with separate licenses.
%
%The channels are generated using QuaDRiGa from the Fraunhofer Heinrich
%Hertz Institute (http://www.quadriga-channel-model.de). This script has
%been tested with QuaDRiGa version 2.0.0-664.
%
%Downling channel matrix quantization is performed using CVX optimization 
%from CVX Research, Inc. (http://cvxr.com/cvx/). This script has been 
%tested with CVX 2.1, using the solver Mosek, version 8.0.0.60.
%

%Empty workspace and close figures
close all;
clear;

%Number of BSs
L = 7; %For small hexagonal grid
%L = 19; %For full hexagonal grid

%Number of UEs in macro cell to represent backhaul of small cells
SCdrop = 2; 
%Thus total number of SCs
L_SC = SCdrop * L; 

%Number of UEs to drop within macro cell
Kdrop = 10;
%Number of UEs to drop within small cell
Kdrop_SC = 2;

%Maximum number of UEs to be served per BS
Kmax = 15;
%Maximum number of UEs to be served per SC
Kmax_SC = 3;

%Pilot reuse factor for macro cells; small cells don't reuse pilots
f = 2;

%Select the number of setups with random UE locations
nbrOfSetups = 1;

%Select the number of channel realizations (means number of subcarriers)
nbrOfSubcarriers = 1200; %3240;
nbrOfSubcarriers_SC = 1560;

%Fractions of UL and DL data for TDD (SC only)
ULfraction_SC = 5/14;
DLfraction_SC = 8/14;


%% Propagation parameters

%Communication bandwidth
B = 20e6; %50e6; %Macro cell tier, FDD
B_SC = 100e6; %Small cell tier, TDD

%Effective bandwidth after removing guardbands
B_effective = 19.1e6; %48.6e6;
B_effective_SC = 95e6;

%Noise figure at the BS and UE (in dB)
noiseFigure = 7;

%Compute noise power
noiseVariancedBm = -174 + 10*log10(B_effective) + noiseFigure;
noiseVariancedBm_SC = -174 + 10*log10(B_effective_SC) + noiseFigure;

%Define total uplink transmit power per UE (mW)
p = 100;
p_SC = 200;

%Maximum downlink transmit power per BS (mW)
Pmax = 1000;
Pmax_SC = 400;

%Select length of coherence block
tau_c = 169;
tau_c_SC = 169;

%Compute pilot length
tau_p = Kmax*f;
tau_p_SC = Kmax_SC;


%Prepare to save simulation results

%Downlink spectral efficiencies - macro and small cells
SE_DL = zeros(tau_p,L,nbrOfSetups);
SE_DL_SC = zeros(tau_p_SC,L_SC,nbrOfSetups);
%Uplink spectral efficiencies
SE_UL = zeros(tau_p,L,nbrOfSetups);
SE_UL_SC = zeros(tau_p_SC,L_SC,nbrOfSetups);

%Downlink user throughputs - macro and small cells
TP_DL = zeros(size(SE_DL));
TP_DL_SC = zeros(size(SE_DL_SC));
%Uplink user throughputs - macro and small cells
TP_UL = zeros(size(SE_UL));
TP_UL_SC = zeros(size(SE_UL_SC));

%Downlink cell throughputs - macro and small cells
TP_DL_total = zeros(L,nbrOfSetups);
TP_DL_SC_total = zeros(L_SC,nbrOfSetups);
TP_DL_SC_total_scaled = zeros(L_SC,nbrOfSetups);
%Uplink cell throughputs - macro and small cells
TP_UL_total = zeros(L,nbrOfSetups);
TP_UL_SC_total = zeros(L_SC,nbrOfSetups);
TP_UL_SC_total_scaled = zeros(L_SC,nbrOfSetups);

%Scaled throughputs for small cells
TP_DL_SC_scaled = zeros(size(TP_DL_SC));
TP_UL_SC_scaled = zeros(size(TP_UL_SC));
%Scaled spectral efficiencies for small cells
SE_DL_SC_scaled = zeros(size(SE_DL_SC));
SE_UL_SC_scaled = zeros(size(SE_UL_SC));

%Macro cell UEs spectral efficiencies, split between backhaul and
%non-backhaul UEs - downlink and uplink
SE_DL_nonbh = zeros(size(SE_DL));
SE_DL_bh = zeros(size(SE_DL));
SE_UL_nonbh = zeros(size(SE_UL));
SE_UL_bh = zeros(size(SE_UL));


%Number of UEs total
nbrOfUEs = zeros(nbrOfSetups,3);
nbrOfUEs_SC = zeros(nbrOfSetups,3);

%Select range of BS antennas
M = 100;
M_SC = 128;

%Select number of polarizations
polarizations = 1;
polarizations_SC = 1;

%Set center frequencies
center_frequency = 2.6e9;
center_frequency_SC = 28e9;

%prepare to store SC UE's demand and their backhaul capacity
store_TP_DL = zeros(L_SC,nbrOfSetups); %backhaul capacity DL
store_TP_UL = zeros(L_SC,nbrOfSetups); %backhaul capacity UL
store_TP_DL_SC_total = zeros(L_SC,nbrOfSetups); %SC UE's demand DL
store_TP_UL_SC_total = zeros(L_SC,nbrOfSetups); %SC UE's demand UL

%prepare to store ratios of SC UE's demand and their backhaul capacity
store_f_d = zeros(L_SC,nbrOfSetups);
store_f_u = zeros(L_SC,nbrOfSetups);


%% Go through all setups

for n = 1:nbrOfSetups
    
    %Output simulation progress
    disp([num2str(n) ' setups out of ' num2str(nbrOfSetups)]);
    
    %Generate channel realizations for current setup
    [H,Rest,activeUEs,pilotPattern,H_SC,Rest_SC,activeUEs_SC,...
    pilotPattern_SC,SCpositions,SCindex,Hbuilder_SC,SCindex_rnd,size_hex] = ...
    functionNetworkSetup_Quadriga(L,SCdrop,Kdrop,Kdrop_SC,B_effective,...
    B_effective_SC,noiseVariancedBm,noiseVariancedBm_SC,Kmax,Kmax_SC,f,...
    M,M_SC,polarizations,polarizations_SC,center_frequency,center_frequency_SC,...
    nbrOfSubcarriers, nbrOfSubcarriers_SC);
    
    %Update how many UEs that have been scheduled
    nbrOfUEs(n) = sum(activeUEs(:));
    %Update how many SC UEs that have been scheduled
    nbrOfUEs_SC(n) = sum(activeUEs_SC(:));
    
    %% Compute DL results
    
    %Compute the prelog factor for the DL TDD (SC only)
    prelogFactorDL_SC = DLfraction_SC*(1-tau_p_SC/tau_c_SC);
   
    %Compute MMSE channel estimates for SCs
    [Hhat_MMSE_SC,C_MMSE_SC,~] = functionChannelEstimates_MMSE(H_SC, ...
        Rest_SC,nbrOfSubcarriers_SC,M_SC,tau_p_SC,L_SC,p_SC);
    
    %Output simulation progress
    disp('Computing DL spectral efficiencies');
    
    %Compute DL spectral efficiencies
    [SE_DL(:,:,n)] = functionComputeSE_DGOB(L,M,H,tau_p,nbrOfSubcarriers,Pmax);
    [SE_DL_SC(:,:,n)] = functionComputeSE_DL_SC(H_SC,Hhat_MMSE_SC, ...
        nbrOfSubcarriers_SC,M_SC,tau_p_SC,L_SC,Hbuilder_SC,Pmax_SC,...
        center_frequency_SC);
    
    %Adjust for TDD ratio
    SE_DL_SC(:,:,n) = prelogFactorDL_SC*SE_DL_SC(:,:,n);
    
    %Delete large matrices
    clear Hhat_MMSE_SC C_MMSE_SC;
        
    
    %% Compute UL results
    
    %20 dB power control
    powerDiffdB = 20;
    
    Hscaled = H;
    RestScaled = Rest;
    Hscaled_SC = H_SC;
    RestScaled_SC = Rest_SC;
    
    %Compute the prelog factor for the UL TDD (SC only)
    prelogFactorUL_SC = ULfraction_SC*(1-tau_p_SC/tau_c_SC);
    
    %Apply the power control policy in (7.11) - macro cells
    for j = 1:L
        
        betaValues = ...
            10*log10(squeeze(sum(sum(Rest(:,:,activeUEs(:,j)==1,j,j),1),2)/M));
        betaMin = min(betaValues);
        
        differenceSNR = betaValues-betaMin;
        backoff = differenceSNR-powerDiffdB;
        backoff(backoff<0) = 0;
        
        activeIndices = find(activeUEs(:,j));
        
        for k = 1:length(activeIndices)
            
            Hscaled(:,:,activeIndices(k),j,:) = ...
                H(:,:,activeIndices(k),j,:)/10^(backoff(k)/20);
            RestScaled(:,:,activeIndices(k),j,:) = ...
                Rest(:,:,activeIndices(k),j,:)/10^(backoff(k)/10);
            
        end
        
    end
    
    %Apply the power control policy in (7.11) - small cells
    for j = 1:L_SC
        
        betaValues_SC = 10*log10(squeeze(sum(sum(Rest_SC(:,:,...
            activeUEs_SC(:,j)==1,j,j),1),2)/M_SC));   
        betaMin_SC = min(betaValues_SC);
        
        differenceSNR_SC = betaValues_SC-betaMin_SC;
        backoff_SC = differenceSNR_SC-powerDiffdB;
        backoff_SC(backoff_SC<0) = 0;
        
        activeIndices_SC = find(activeUEs_SC(:,j));
        
        for k = 1:length(activeIndices_SC)
            
            Hscaled_SC(:,:,activeIndices_SC(k),j,:) = ...
                H_SC(:,:,activeIndices_SC(k),j,:)/10^(backoff_SC(k)/20);
            RestScaled_SC(:,:,activeIndices_SC(k),j,:) = ...
                Rest_SC(:,:,activeIndices_SC(k),j,:)/10^(backoff_SC(k)/10);
            
        end
        
    end
    
    %Compute MMSE channel estimates
    [Hhat_MMSE,C_MMSE,~] = functionChannelEstimates_MMSE(Hscaled,...
        RestScaled,nbrOfSubcarriers,M,tau_p,L,p);
    [Hhat_MMSE_SC,C_MMSE_SC,~] = functionChannelEstimates_MMSE(Hscaled_SC,...
        RestScaled_SC,nbrOfSubcarriers_SC,M_SC,tau_p_SC,L_SC,p_SC);
    
    %Output simulation progress
    disp('Computing UL spectral efficiencies');
    
    %Compute UL SEs using the hardening bound / from MMSE channel estimation
    [SE_UL(:,:,n)] = functionComputeSE_UL(Hscaled,Hhat_MMSE,...
        C_MMSE,tau_c,tau_p,nbrOfSubcarriers,M,tau_p,L,p,1,1);  
    [SE_UL_SC(:,:,n)] = functionComputeSE_UL_SC(Hscaled_SC,Hhat_MMSE_SC,...
        nbrOfSubcarriers_SC,M_SC,tau_p_SC,L_SC,Hbuilder_SC,Pmax_SC,...
        center_frequency_SC);
    
    %Adjust for TDD ratio
    SE_UL_SC(:,:,n) = prelogFactorUL_SC*SE_UL_SC(:,:,n);
    
    %Delete large matrices
    clear C_MMSE Hhat_MMSE_SC C_MMSE_SC; %Hhat_MMSE 
    
    %Delete large matrices
    clear H Rest RestScaled; %Hscaled
    clear H_SC Rest_SC Hscaled_SC RestScaled_SC;
    
    
    %Convert spectral efficiencies to tputs, [Mbit/s]
    TP_DL(:,:,n) = (B_effective/1e6)*SE_DL(:,:,n);
    TP_DL_SC(:,:,n) = (B_effective_SC/1e6)*SE_DL_SC(:,:,n);
    TP_UL(:,:,n) = (B_effective/1e6)*SE_UL(:,:,n);
    TP_UL_SC(:,:,n) = (B_effective_SC/1e6)*SE_UL_SC(:,:,n);
    
    %Store cell throughputs
    TP_DL_total(:,n) = sum(TP_DL(:,:,n),1); %DL cell throughputs of 
    %macro layer
    TP_UL_total(:,n) = sum(TP_UL(:,:,n),1); %UL cell throughputs of 
    %macro layer
    
    %Adjust SC spectral efficiencies and throughputs depending on backhaul
    %throughput (i.e. throughput of corresponding macro UEs)
    
    TP_DL_SC_total(:,n) = sum(TP_DL_SC(:,:,n),1); %DL cell throughputs of 
    %SC layer
    TP_UL_SC_total(:,n) = sum(TP_UL_SC(:,:,n),1); %UL cell throughputs of 
    %SC layer
    
    [k_ind,l_ind] = find(SCindex_rnd);
    

    
    for i = 1:L_SC
        
        %ratios of SC UE's demand and their backhaul capacity
        f_d = 1;
        f_u = 1;
        
        store_TP_DL(i,n) = TP_DL(k_ind(i),l_ind(i),n);
        store_TP_UL(i,n) = TP_UL(k_ind(i),l_ind(i),n);
        store_TP_DL_SC_total(i,n) = TP_DL_SC_total(SCindex_rnd(k_ind(i),l_ind(i)),n);
        store_TP_UL_SC_total(i,n) = TP_UL_SC_total(SCindex_rnd(k_ind(i),l_ind(i)),n);
        
        %Check if small cell total DL tput exceeds its backhaul DL tput
        if TP_DL(k_ind(i),l_ind(i),n) < ...
                TP_DL_SC_total(SCindex_rnd(k_ind(i),l_ind(i)),n)
            %Calculate ratio of small cell total DL tput and its backhaul 
            %DL tput
            f_d = TP_DL_SC_total(SCindex_rnd(k_ind(i),l_ind(i)),n) / ...
                TP_DL(k_ind(i),l_ind(i),n);
        end
        
        %Check UL as well
        if TP_UL(k_ind(i),l_ind(i),n) < ...
                TP_UL_SC_total(SCindex_rnd(k_ind(i),l_ind(i)),n)
            %Calculate ratio of small cell total DL tput and its backhaul 
            %UL tput
            f_u = TP_UL_SC_total(SCindex_rnd(k_ind(i),l_ind(i)),n) / ...
                TP_UL(k_ind(i),l_ind(i),n);
        end
        
        TP_DL_SC_scaled(:,i,n) = TP_DL_SC(:,i,n) / f_d;
        SE_DL_SC_scaled(:,i,n) = SE_DL_SC(:,i,n) / f_d;
        
        TP_UL_SC_scaled(:,i,n) = TP_UL_SC(:,i,n) / f_u;
        SE_UL_SC_scaled(:,i,n) = SE_UL_SC(:,i,n) / f_u;
        
        store_f_d(i,n) = f_d;
        store_f_u(i,n) = f_u;

    end
    
    %alternative way to calculate ratio of demand and backhaul capacity
%     store_f_d_a = zeros(L_SC,1);
%     store_f_u_a = zeros(L_SC,1);
%     store_TP_DL = sort(store_TP_DL);
%     store_TP_DL_SC_total = sort(store_TP_DL_SC_total);
%     store_TP_UL = sort(store_TP_UL);
%     store_TP_UL_SC_total = sort(store_TP_UL_SC_total);
%     for i = 1:L_SC
%         
%         f_d_a = 1;
%         f_u_a = 1;
%         
%         %Check if small cell total DL tput exceeds its backhaul DL tput
%         if store_TP_DL(i) < store_TP_DL_SC_total(i)
%             %Calculate ratio of small cell total DL tput and its backhaul 
%             %DL tput
%             f_d_a = store_TP_DL_SC_total(i) / store_TP_DL(i);
%         end
%         
%         %Check UL as well
%         if store_TP_UL(i) < store_TP_UL_SC_total(i)
%             %Calculate ratio of small cell total DL tput and its backhaul 
%             %UL tput
%             f_u_a = store_TP_UL_SC_total(i) / store_TP_UL(i);
%         end
%         
%         TP_DL_SC_scaled(:,i,n) = TP_DL_SC(:,i,n) / f_d_a;
%         SE_DL_SC_scaled(:,i,n) = SE_DL_SC(:,i,n) / f_d_a;
%         
%         TP_UL_SC_scaled(:,i,n) = TP_UL_SC(:,i,n) / f_u_a;
%         SE_UL_SC_scaled(:,i,n) = SE_UL_SC(:,i,n) / f_u_a;
%         
%         store_f_d_a(i) = f_d_a;
%         store_f_u_a(i) = f_u_a;
%         
%     end

    %remove too small values
%     for i = 1:L_SC
%         if TP_DL(k_ind(i),l_ind(i)) < 50 || TP_UL(k_ind(i),l_ind(i)) < 50
%             k_ind(i) = [];
%             l_ind(i) = [];
%             store_TP_DL(i) = [];
%             store_TP_UL(i) = [];
%             store_TP_DL_SC_total(i) = [];
%             store_TP_UL_SC_total(i) = [];
%             store_f_d(i) = [];
%             store_f_u(i) = [];
%     end
    
    %Calculate scaled metrics for DL and UL cell throughputs of small cell
    %layer
    TP_DL_SC_total_scaled(:,n) = sum(TP_DL_SC_scaled(:,:,n),1); 
    TP_UL_SC_total_scaled(:,n) = sum(TP_UL_SC_scaled(:,:,n),1); 
    
    %Create separate results for non-backhaul macro UEs and backhaul (SC)
    %macro UEs
    
    %Initialize non-backhaul arrays with full array of spectral
    %efficiencies of all macro UEs
    SE_DL_nonbh(:,:,n) = SE_DL(:,:,n);
    SE_UL_nonbh(:,:,n) = SE_UL(:,:,n);
    
    for i = 1:L_SC
        
        %Fill backhaul array with spectral efficiencies of macro UEs
        %representing small cell backhaul
        SE_DL_bh(k_ind(i),l_ind(i),n) = SE_DL(k_ind(i),l_ind(i),n);
        SE_UL_bh(k_ind(i),l_ind(i),n) = SE_UL(k_ind(i),l_ind(i),n);
        
        %Clear spectral efficiencies of macro UEs representing small cell 
        %backhaul from non-backhaul array
        SE_DL_nonbh(k_ind(i),l_ind(i),n) = 0;
        SE_UL_nonbh(k_ind(i),l_ind(i),n) = 0;
    
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %MSE for the estimate of H
    for i = 1:L
        for k = 1:tau_p
            MSE_H(k,i) = sum(abs(Hscaled(:,:,k,i,i) - Hhat_MMSE(:,:,k,i,i)).^2,'all');
        end
    end
    MSE_H_bh(n) = mean(MSE_H(SCindex_rnd==0));
    MSE_H_nonbh(n) = mean(MSE_H(SCindex_rnd>0));
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

end


%% Plot the simulation results

%DL macro tier
SE_DL_active = SE_DL(:,:,:);
SE_DL_active = sort(SE_DL_active(find(SE_DL_active>0)));
%DL macro tier - non-backhaul UEs only
SE_DL_nonbh_active = SE_DL_nonbh(:,:,:);
SE_DL_nonbh_active = sort(SE_DL_nonbh_active(find(SE_DL_nonbh_active>0)));
%DL macro tier - backhaul UEs only
SE_DL_bh_active = SE_DL_bh(:,:,:);
SE_DL_bh_active = sort(SE_DL_bh_active(find(SE_DL_bh_active>0)));
%DL micro tier
SE_DL_SC_active = SE_DL_SC(:,:,:);
SE_DL_SC_active = sort(SE_DL_SC_active(find(SE_DL_SC_active>0)));
%DL micro tier - scaled
SE_DL_SC_scaled_active = prelogFactorDL_SC*SE_DL_SC_scaled(:,:,:);
SE_DL_SC_scaled_active = ...
    sort(SE_DL_SC_scaled_active(find(SE_DL_SC_scaled_active>0)));

%UL macro tier
SE_UL_active = SE_UL(:,:,:);
SE_UL_active = sort(SE_UL_active(find(SE_UL_active>0)));
%UL macro tier - non-backhaul UEs only
SE_UL_nonbh_active = SE_UL_nonbh(:,:,:);
SE_UL_nonbh_active = sort(SE_UL_nonbh_active(find(SE_UL_nonbh_active>0)));
%UL macro tier - backhaul UEs only
SE_UL_bh_active = SE_UL_bh(:,:,:);
SE_UL_bh_active = sort(SE_UL_bh_active(find(SE_UL_bh_active>0)));
%UL micro tier
SE_UL_SC_active = SE_UL_SC(:,:,:);
SE_UL_SC_active = sort(SE_UL_SC_active(find(SE_UL_SC_active>0)));
%UL micro tier - scaled
SE_UL_SC_scaled_active = SE_UL_SC_scaled(:,:,:);
SE_UL_SC_scaled_active = ...
    sort(SE_UL_SC_scaled_active(find(SE_UL_SC_scaled_active>0)));

%Extract total number of UEs
Ktotal = sum(nbrOfUEs(:));
Ktotal_SC = sum(nbrOfUEs_SC(:));

%Set line styles
%Macro - DL and UL plots
Macro_all = 'r--'; %MMSE_DGOB for DL, MMSE_RZF for UL
Macro_nonbh = 'm--';
Macro_bh = 'b--';
%Micro - DL and UL plots
Micro_initial = 'g--';  %MMSE_OMP for DL and UL
Micro_scaled = 'c--';
%Cell throughputs
Macro_cell_tput_DL = 'r-o';
Macro_cell_tput_UL = 'b-o';
Micro_cell_tput_DL = 'r-o';
Micro_cell_tput_UL = 'b-o';
Micro_cell_tput_DL_scaled = 'r-*';
Micro_cell_tput_UL_scaled = 'b-*';

%Plot DL user throughput per macrocell UE
figure(11);
hold on; box on; grid on;
plot((B_effective/1e6)*SE_DL_active,...
    linspace(0,1,Ktotal),Macro_all,'LineWidth',1);
plot((B_effective/1e6)*SE_DL_nonbh_active,...
    linspace(0,1,length(SE_DL_nonbh_active)),Macro_nonbh,'LineWidth',1);
plot((B_effective/1e6)*SE_DL_bh_active,...
    linspace(0,1,length(SE_DL_bh_active)),Macro_bh,'LineWidth',1);
legend('All macro UEs','Mobile macro UEs','Backhaul macro UEs',...
    'Location','SouthEast','AutoUpdate','off');
xlabel('DL throughput per macrocell UE [Mbit/s]');
ylabel('CDF');
xlim([0 200]);

%Plot DL user throughput per small cell UE
figure(21);
hold on; box on; grid on;
plot((B_effective_SC/1e6)*SE_DL_SC_active,...
    linspace(0,1,Ktotal_SC),Micro_initial,'LineWidth',1);
plot((B_effective_SC/1e6)*SE_DL_SC_scaled_active,...
    linspace(0,1,Ktotal_SC),Micro_scaled,'LineWidth',1);
legend('Small cell UEs','Small cell UEs - scaled',...
    'Location','SouthEast','AutoUpdate','off');
xlabel('DL throughput per small cell UE [Mbit/s]');
ylabel('CDF');
xlim([0 200]);

%Plot UL user throughput per macrocell UE
figure(12);
hold on; box on; grid on;
plot((B_effective/1e6)*SE_UL_active,...
    linspace(0,1,Ktotal),Macro_all,'LineWidth',1);
plot((B_effective/1e6)*SE_UL_nonbh_active,...
    linspace(0,1,length(SE_UL_nonbh_active)),Macro_nonbh,'LineWidth',1);
plot((B_effective/1e6)*SE_UL_bh_active,...
    linspace(0,1,length(SE_UL_bh_active)),Macro_bh,'LineWidth',1);
legend('All macro UEs','Mobile macro UEs','Backhaul macro UEs',...
    'Location','SouthEast','AutoUpdate','off');
xlabel('UL throughput per macrocell UE [Mbit/s]');
ylabel('CDF');
xlim([0 150]);

%Plot UL user throughput per small cell UE
figure(22);
hold on; box on; grid on;
plot((B_effective_SC/1e6)*SE_UL_SC_active,...
    linspace(0,1,Ktotal_SC),Micro_initial,'LineWidth',1);
plot((B_effective_SC/1e6)*SE_UL_SC_scaled_active,...
    linspace(0,1,Ktotal_SC),Micro_scaled,'LineWidth',1);
legend('Small cell UEs','Small cell UEs - scaled',...
    'Location','SouthEast','AutoUpdate','off');
xlabel('UL throughput per small cell UE [Mbit/s]');
ylabel('CDF');
xlim([0 150]);

%Plot statistics: user throughputs, both tiers
f = figure(67);
set(f,'Position', [200 200 1200 400]);
uit = uitable(f);
uit.ColumnName = {'Type of UEs','Median DL tput','Median UL tput',...
    'Average DL tput','Average UL tput',...
    'p5 DL tput', 'p5 UL tput',...
    'p95 DL tput', 'p95 UL tput'};
uit.Data = {'Macro: all UEs',...
    median((B_effective/1e6)*SE_DL_active),...
    median((B_effective/1e6)*SE_UL_active),...
    mean((B_effective/1e6)*SE_DL_active),...
    mean((B_effective/1e6)*SE_UL_active),...
    prctile((B_effective/1e6)*SE_DL_active,5),...
    prctile((B_effective/1e6)*SE_UL_active,5),...
    prctile((B_effective/1e6)*SE_DL_active,95),...
    prctile((B_effective/1e6)*SE_UL_active,95);...
    'Macro: non-backhaul UEs',...
    median((B_effective/1e6)*SE_DL_nonbh_active),...
    median((B_effective/1e6)*SE_UL_nonbh_active),...
    mean((B_effective/1e6)*SE_DL_nonbh_active),...
    mean((B_effective/1e6)*SE_UL_nonbh_active),...
    prctile((B_effective/1e6)*SE_DL_nonbh_active,5),...
    prctile((B_effective/1e6)*SE_UL_nonbh_active,5),...
    prctile((B_effective/1e6)*SE_DL_nonbh_active,95),...
    prctile((B_effective/1e6)*SE_UL_nonbh_active,95);...
    'Macro: backhaul UEs',...
    median((B_effective/1e6)*SE_DL_bh_active),...
    median((B_effective/1e6)*SE_UL_bh_active),...
    mean((B_effective/1e6)*SE_DL_bh_active),...
    mean((B_effective/1e6)*SE_UL_bh_active),...
    prctile((B_effective/1e6)*SE_DL_bh_active,5),...
    prctile((B_effective/1e6)*SE_UL_bh_active,5),...
    prctile((B_effective/1e6)*SE_DL_bh_active,95),...
    prctile((B_effective/1e6)*SE_UL_bh_active,95);...
    'Small cell UEs',...
    median((B_effective_SC/1e6)*SE_DL_SC_active),...
    median((B_effective_SC/1e6)*SE_UL_SC_active),...
    mean((B_effective_SC/1e6)*SE_DL_SC_active),...
    mean((B_effective_SC/1e6)*SE_UL_SC_active),...
    prctile((B_effective_SC/1e6)*SE_DL_SC_active,5),...
    prctile((B_effective_SC/1e6)*SE_UL_SC_active,5),...
    prctile((B_effective_SC/1e6)*SE_DL_SC_active,95),...
    prctile((B_effective_SC/1e6)*SE_UL_SC_active,95);...
    'Small cell UEs: scaled',...
    median((B_effective_SC/1e6)*SE_DL_SC_scaled_active),...
    median((B_effective_SC/1e6)*SE_UL_SC_scaled_active),...
    mean((B_effective_SC/1e6)*SE_DL_SC_scaled_active),...
    mean((B_effective_SC/1e6)*SE_UL_SC_scaled_active),...
    prctile((B_effective_SC/1e6)*SE_DL_SC_scaled_active,5),...
    prctile((B_effective_SC/1e6)*SE_UL_SC_scaled_active,5),...
    prctile((B_effective_SC/1e6)*SE_DL_SC_scaled_active,95),...
    prctile((B_effective_SC/1e6)*SE_UL_SC_scaled_active,95);...
    };
uit.Position = [20 20 1160 360];
uit.ColumnWidth = {150,100,100,100,100,100,100,100,100};

%Plot cell throughput CDFs

%Plot DL and UL cell throughput per macrocell
figure(13);
hold on; box on; grid on;
plot(sort(TP_DL_total(:)),...
    linspace(0,1,length(TP_DL_total(:))),Macro_cell_tput_DL,'LineWidth',1);
plot(sort(TP_UL_total(:)),...
    linspace(0,1,length(TP_UL_total(:))),Macro_cell_tput_UL,'LineWidth',1);
legend('Macro cell DL throughput','Macro cell UL throughput',...
    'Location','SouthEast','AutoUpdate','off');
xlabel('Macro cell tier: cell throughput [Mbit/s]');
ylabel('CDF');
xlim([0 1200]);

%Plot DL and UL cell throughput per small cell (+ scaled)
figure(23);
hold on; box on; grid on;
plot(sort(TP_DL_SC_total(:)),...
    linspace(0,1,length(TP_DL_SC_total(:))),...
    Micro_cell_tput_DL,'LineWidth',1);
plot(sort(TP_UL_SC_total(:)),...
    linspace(0,1,length(TP_UL_SC_total(:))),...
    Micro_cell_tput_UL,'LineWidth',1);
plot(sort(TP_DL_SC_total_scaled(:)),...
    linspace(0,1,length(TP_DL_SC_total_scaled(:))),...
    Micro_cell_tput_DL_scaled,'LineWidth',1);
plot(sort(TP_UL_SC_total_scaled(:)),...
    linspace(0,1,length(TP_UL_SC_total_scaled(:))),...
    Micro_cell_tput_UL_scaled,'LineWidth',1);
legend('Small cell DL throughput','Small cell UL throughput',...
    'Small cell DL throughput (scaled)','Small cell UL throughput (scaled)',...
    'Location','SouthEast','AutoUpdate','off');
xlabel('Small cell tier: cell throughput [Mbit/s]');
ylabel('CDF');
xlim([0 600]);

%Plot statistics: cell throughputs, both tiers
f = figure(68);
set(f,'Position', [200 200 900 400]);
uit = uitable(f);
uit.ColumnName = {'Type of cells','Median DL cell throughput',...
    'Median UL cell throughput','Average DL cell throughput',...
    'Average UL cell throughput'};
uit.Data = {'Macro cells',...
    median(TP_DL_total(:)),...
    median(TP_UL_total(:)),...
    mean(TP_DL_total(:)),...
    mean(TP_UL_total(:));...
    'Small cells',...
    median(TP_DL_SC_total(:)),...
    median(TP_UL_SC_total(:)),...
    mean(TP_DL_SC_total(:)),...
    mean(TP_UL_SC_total(:));...
    'Small cells (scaled)',...
    median(TP_DL_SC_total_scaled(:)),...
    median(TP_UL_SC_total_scaled(:)),...
    mean(TP_DL_SC_total_scaled(:)),...
    mean(TP_UL_SC_total_scaled(:));...
    'SCs: capacity loss due to scaling, %',...
    (1 - median(TP_DL_SC_total_scaled(:))/median(TP_DL_SC_total(:)))*100,...
    (1 - median(TP_UL_SC_total_scaled(:))/median(TP_UL_SC_total(:)))*100,...
    (1 - mean(TP_DL_SC_total_scaled(:))/mean(TP_DL_SC_total(:)))*100,...
    (1 - mean(TP_UL_SC_total_scaled(:))/mean(TP_UL_SC_total(:)))*100;...
    };
uit.Position = [20 20 860 360];
uit.ColumnWidth = {200,150,150,150,150};


%Plot statistics: area throughputs, 2-layer system
f = figure(69);
set(f,'Position', [200 200 900 400]);
total_area_km2 = 3 * sqrt(3) * size_hex^2 / 2 * 7 / 1e6;
DL_area_tput = (sum(TP_DL_total(:))+...
    sum(TP_DL_SC_total(:))) / (total_area_km2*n) * 10e-3;
DL_area_tput_scaled = (sum(TP_DL_total(:))+...
    sum(TP_DL_SC_total_scaled(:))) / (total_area_km2*n) * 10e-3;
UL_area_tput = (sum(TP_UL_total(:))+...
    sum(TP_UL_SC_total(:))) / (total_area_km2*n) * 10e-3;
UL_area_tput_scaled = (sum(TP_UL_total(:))+...
    sum(TP_UL_SC_total_scaled(:))) / (total_area_km2*n) * 10e-3;
uit = uitable(f);
uit.ColumnName = {'DL/UL','Total area throughput non-scaled, Gbit/s/km2',...
    'Total area throughput scaled, Gbit/s/km2','Capacity loss due to scaling, %'};
uit.Data = {'DL',...
    DL_area_tput,...
    DL_area_tput_scaled,...
    (1 - DL_area_tput_scaled/DL_area_tput)*100;...
    'UL',...
    UL_area_tput,...
    UL_area_tput_scaled,...
    (1 - UL_area_tput_scaled/UL_area_tput)*100;...
    };
uit.Position = [20 20 860 360];
uit.ColumnWidth = {50,250,250,250};


%Plot various additional statistics
f = figure(70);
set(f,'Position', [200 200 900 400]);

%Share of small cells with enough backhaul throughput to cover demand
%without scaling (without any backhaul loss due to scaling)
enough_backhaul_tput_share_DL = length(store_f_d(store_f_d==1)) / ...
    length(store_f_d(:))*100; %by DL
enough_backhaul_tput_share_UL = length(store_f_u(store_f_u==1)) / ...
    length(store_f_u(:))*100; %by UL
store_f_all(:) = store_f_d(:) + store_f_u(:);
enough_backhaul_tput_share_all = length(store_f_all(store_f_all==2)) / ...
    length(store_f_all(:))*100; %by all
%another way to calculate total capacity loss - by dividing total
%demand in small cells layer by total backhaul capacity
backhaul_loss_total_DL = (1 - sum(store_TP_DL(:))/sum(store_TP_DL_SC_total(:)))*100;
backhaul_loss_total_UL = (1 - sum(store_TP_UL(:))/sum(store_TP_UL_SC_total(:)))*100;

uit = uitable(f);
uit.ColumnName = {'KPI','Value','Unit'};
uit.Data = {'Share of SCs with sufficient backhaul without scaling, by DL',...
    enough_backhaul_tput_share_DL,...
    '%';...
    'Share of SCs with sufficient backhaul without scaling, by UL',...
    enough_backhaul_tput_share_UL,...
    '%';...
    'Share of SCs with sufficient backhaul without scaling, by DL & UL',...
    enough_backhaul_tput_share_all,...
    '%';...
    'Total capacity loss in DL (1 - sum demand in SCs / sum backhaul capacity)',...
    backhaul_loss_total_DL,...
    '%';...
    'Total capacity loss in UL (1 - sum demand in SCs / sum backhaul capacity)',...
    backhaul_loss_total_UL,...
    '%';...
    'MSE of channel estimation, backhaul UEs',...
    mean(MSE_H_bh),...
    '';...
    'MSE of channel estimation, non-backhaul UEs',...
    mean(MSE_H_nonbh),...
    '';...
    };
uit.Position = [20 20 860 360];
uit.ColumnWidth = {500,100,100};
